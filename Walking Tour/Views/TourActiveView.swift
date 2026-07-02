import SwiftUI

struct TourActiveView: View {
    @Bindable var viewModel: TourViewModel
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedStopIndex = 0
    @State private var panelExtent: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var stopPendingRemoval: TourStop?

    var body: some View {
        if let tour = viewModel.tour {
            GeometryReader { geometry in
                let metrics = StopPanelMetrics(size: geometry.size)
                let extent = resolvedExtent(metrics: metrics)
                let panelHeight = metrics.panelHeight(for: extent)
                let mapIsVisible = panelHeight < geometry.size.height - 24

                ZStack(alignment: .bottom) {
                    TourMapView(
                        tour: tour,
                        routePolyline: viewModel.routePolyline,
                        selectedStopID: viewModel.selectedStop?.id,
                        currentStopIndex: viewModel.navigationManager.isActive
                            ? viewModel.navigationManager.currentStopIndex
                            : selectedStopIndex,
                        followUser: viewModel.navigationManager.isActive,
                        showUserLocation: viewModel.navigationManager.isActive
                            && viewModel.locationService.currentLocation != nil,
                        onSelectStop: { stop in
                            selectStop(stop, in: tour)
                            collapsePanel()
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(mapIsVisible)
                    .accessibilityHidden(!mapIsVisible)

                    stopPanel(tour, metrics: metrics, extent: extent)
                        .frame(width: geometry.size.width, height: panelHeight)
                        .gesture(panelDragGesture(metrics: metrics))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .onAppear {
                initializeSelection(for: tour)
            }
            .onChange(of: tour.id) { _, _ in
                initializeSelection(for: tour)
                collapsePanel(animated: false)
            }
            .sheet(item: $viewModel.directionsStop) { stop in
                StopDirectionsView(
                    stop: stop,
                    tour: tour,
                    origin: viewModel.originCoordinate(for: stop, in: tour),
                    distanceUnit: appSettings.distanceUnit
                )
            }
            .sheet(item: $viewModel.wikipediaStop) { stop in
                WikipediaArticleView(stop: stop)
            }
            .sheet(isPresented: $viewModel.showAddStopSheet) {
                AddStopSheet(viewModel: viewModel)
            }
            .confirmationDialog(
                "Remove \(stopPendingRemoval?.name ?? "this stop") from your tour?",
                isPresented: Binding(
                    get: { stopPendingRemoval != nil },
                    set: { if !$0 { stopPendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Stop", role: .destructive) {
                    if let stop = stopPendingRemoval {
                        Task { await viewModel.removeStop(stop) }
                    }
                    stopPendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    stopPendingRemoval = nil
                }
            }
        }
    }

    private func stopPanel(
        _ tour: WalkingTour,
        metrics: StopPanelMetrics,
        extent: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            panelDragHandle(extent: extent)

            if viewModel.navigationManager.isActive {
                LiveNavigationBar(viewModel: viewModel)
            }

            if extent < 0.92 {
                tourSummaryBar(tour)
                    .opacity(Double(max(0, 1 - extent * 1.15)))
            }

            stopPager(tour, isExpanded: extent > 0.7, extent: extent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.cardBackground(for: colorScheme))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: extent > 0.95 ? 0 : 18, topTrailingRadius: extent > 0.95 ? 0 : 18))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: extent > 0.95 ? 0 : 12, y: -4)
    }

    private func panelDragHandle(extent: CGFloat) -> some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 40, height: 5)

            Text(extent > 0.7 ? "Swipe down for map" : "Swipe up for full details")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .accessibilityLabel(extent > 0.7 ? "Collapse stop details" : "Expand stop details")
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            togglePanel()
        }
    }

    private func stopPager(
        _ tour: WalkingTour,
        isExpanded: Bool,
        extent: CGFloat
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stop \(selectedStopIndex + 1) of \(tour.stops.count)")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accentText(for: colorScheme))
                    Text(isExpanded ? "Swipe down for map · swipe for stops" : "Swipe stops · swipe up for details")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        viewModel.presentAddStopOptions()
                    } label: {
                        Label("Add a Stop", systemImage: "plus.circle")
                    }

                    Button(role: .destructive) {
                        if let current = tour.stops[safe: selectedStopIndex] {
                            stopPendingRemoval = current
                        }
                    } label: {
                        Label("Remove This Stop", systemImage: "minus.circle")
                    }
                    .disabled(tour.stops.count <= 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(AppTheme.accentText(for: colorScheme))
                }
                .disabled(viewModel.isUpdatingStops)

                if !viewModel.navigationManager.isActive {
                    Button {
                        viewModel.startNavigation()
                    } label: {
                        Label("Start", systemImage: "location.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary(for: colorScheme))
                    .controlSize(.small)
                } else {
                    Button("Stop Nav") {
                        viewModel.stopNavigation()
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)

            if viewModel.isUpdatingStops {
                ProgressView("Updating route…")
                    .font(.caption2)
                    .padding(.horizontal)
            }

            TabView(selection: $selectedStopIndex) {
                ForEach(Array(tour.stops.enumerated()), id: \.element.id) { index, stop in
                    StopDetailView(
                        stop: stop,
                        stepNumber: index + 1,
                        distanceUnit: appSettings.distanceUnit,
                        onShowDirections: { viewModel.showDirections(for: stop) },
                        onShowWikipedia: { viewModel.showWikipedia(for: stop) }
                    )
                    .padding(.horizontal, 12)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            .onChange(of: selectedStopIndex) { _, newIndex in
                guard tour.stops.indices.contains(newIndex) else { return }
                viewModel.selectedStop = tour.stops[newIndex]
                if viewModel.navigationManager.isActive {
                    viewModel.jumpToStop(index: newIndex)
                }
            }
            .onChange(of: tour.stops.count) { _, newCount in
                if selectedStopIndex >= newCount {
                    selectedStopIndex = max(0, newCount - 1)
                }
            }

            StopPageIndicator(
                count: tour.stops.count,
                selectedIndex: selectedStopIndex
            )
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    private func tourSummaryBar(_ tour: WalkingTour) -> some View {
        HStack {
            Label(tour.formattedDistance(unit: appSettings.distanceUnit), systemImage: "arrow.left.and.right")
            Spacer()
            Label(tour.formattedDuration(), systemImage: "clock")
            Spacer()
            Label(tour.preferences.routeShape.label, systemImage: tour.preferences.routeShape == .loop ? "arrow.trianglehead.counterclockwise" : "arrow.right")
        }
        .font(.caption.bold())
        .foregroundStyle(AppTheme.accentText(for: colorScheme))
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(AppTheme.summaryBarBackground(for: colorScheme))
    }

    private func panelDragGesture(metrics: StopPanelMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                let translation = value.translation
                guard abs(translation.height) > abs(translation.width) * 0.85 else { return }
                dragTranslation = translation.height
            }
            .onEnded { value in
                let range = metrics.expandableRange
                guard range > 0 else {
                    dragTranslation = 0
                    return
                }

                let snapExtent = min(1, max(0, panelExtent - dragTranslation / range))
                let shouldExpand = snapExtent > 0.45 || value.velocity.height < -450

                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.12)) {
                    panelExtent = shouldExpand ? 1 : 0
                    dragTranslation = 0
                }
            }
    }

    private func resolvedExtent(metrics: StopPanelMetrics) -> CGFloat {
        guard metrics.expandableRange > 0 else { return panelExtent }
        let extent = panelExtent - dragTranslation / metrics.expandableRange
        return min(1, max(0, extent))
    }

    private func togglePanel() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            panelExtent = panelExtent > 0.45 ? 0 : 1
            dragTranslation = 0
        }
    }

    private func collapsePanel(animated: Bool = true) {
        let update = {
            panelExtent = 0
            dragTranslation = 0
        }
        if animated {
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), update)
        } else {
            update()
        }
    }

    private func initializeSelection(for tour: WalkingTour) {
        guard !tour.stops.isEmpty else { return }
        if let selected = viewModel.selectedStop,
           let index = tour.stops.firstIndex(where: { $0.id == selected.id }) {
            selectedStopIndex = index
        } else {
            selectedStopIndex = 0
            viewModel.selectedStop = tour.stops[0]
        }
    }

    private func selectStop(_ stop: TourStop, in tour: WalkingTour) {
        viewModel.selectedStop = stop
        if let index = tour.stops.firstIndex(where: { $0.id == stop.id }) {
            selectedStopIndex = index
        }
        if viewModel.navigationManager.isActive,
           let index = tour.stops.firstIndex(where: { $0.id == stop.id }) {
            viewModel.jumpToStop(index: index)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct StopPanelMetrics {
    let collapsedHeight: CGFloat = 360
    let size: CGSize

    var expandedHeight: CGFloat {
        size.height
    }

    var expandableRange: CGFloat {
        max(0, expandedHeight - collapsedHeight)
    }

    func panelHeight(for extent: CGFloat) -> CGFloat {
        collapsedHeight + expandableRange * min(1, max(0, extent))
    }
}

private struct StopPageIndicator: View {
    let count: Int
    let selectedIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selectedIndex
                        ? AppTheme.primary(for: colorScheme)
                        : Color.secondary.opacity(colorScheme == .dark ? 0.35 : 0.25))
                    .frame(width: index == selectedIndex ? 8 : 6, height: index == selectedIndex ? 8 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stop \(selectedIndex + 1) of \(count)")
    }
}
