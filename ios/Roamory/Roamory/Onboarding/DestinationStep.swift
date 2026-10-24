import RoamoryKit
import SwiftUI

/// Step 2 (PRD FR-002): continent, then country, then city, on a globe that swoops in as you choose.
/// The rows under the globe and the breadcrumb chips do the same thing as tapping the globe.
struct DestinationStep: View {
    let catalog: OnboardingCatalog
    @Binding var continent: String
    @Binding var country: String
    @Binding var city: String
    /// The globe spins at world view for a moment before flying to a saved choice.
    @State private var revealed = false

    private var currentContinent: Continent? { catalog.continents.first { $0.name == continent } }
    private var currentCountry: Country? { currentContinent?.countries.first { $0.name == country } }
    private var currentCity: City? { currentCountry?.cities.first { $0.name == city } }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height * 0.5)
            VStack(alignment: .leading, spacing: 14) {
                globe(side: side)
                    .frame(width: geo.size.width, height: side)
                breadcrumb
                rows
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(0.9))
            revealed = true
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: continent)
        .sensoryFeedback(.success, trigger: city) { _, new in !new.isEmpty }
    }

    /// Clipped to the world-view silhouette, so zooming in reads as looking closer through the same globe.
    private func globe(side: CGFloat) -> some View {
        ZStack {
            RadialGradient(colors: [Color(hex: "#3b82f6").opacity(0.35), .clear], center: .center,
                           startRadius: side * 0.3, endRadius: side * 0.62)
            GlobeView(
                catalog: catalog,
                focusedContinent: currentContinent?.id,
                focus: revealed ? focus : nil,
                distance: revealed ? distance : GlobeView.worldDistance,
                pins: revealed ? currentCountry?.cities ?? [] : [],
                selectedPin: currentCity?.name,
                onTapContinent: chooseContinent,
                onTapPin: { chooseCity($0.name) }
            )
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Color(hex: "#3b82f6").opacity(0.25), lineWidth: 1) }
        }
    }

    private var focus: GeoPoint? { currentCity?.location ?? currentCountry?.center ?? currentContinent?.center }

    /// Close enough that the whole continent, or all of the country's cities, fill most of the globe.
    private var distance: Double {
        func fit(_ points: [GeoPoint], around center: GeoPoint) -> Double {
            GeoMath.cameraDistance(fitting: points, around: center, fieldOfView: GlobeView.fieldOfView, fill: 0.9,
                                   range: GlobeView.closestDistance...GlobeView.worldDistance)
        }
        if let country = currentCountry, let focus { return fit(country.cities.map(\.location), around: focus) }
        if let continent = currentContinent { return fit(continent.outlines.flatMap { $0 }, around: continent.center) }
        return GlobeView.worldDistance
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            Chip(title: "World", systemImage: "globe", on: currentContinent == nil) {
                set(continent: "", country: "", city: "")
            }
            if let c = currentContinent {
                Chip(title: c.name, on: currentCountry == nil) { set(continent: c.name, country: "", city: "") }
            }
            if let c = currentCountry {
                Chip(title: c.name, on: currentCity == nil) { set(continent: continent, country: c.name, city: "") }
            }
            if let c = currentCity {
                Chip(title: c.name, on: true) {}
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: [continent, country, city])
    }

    /// What can be chosen at the current level, as dark cards; the chosen one has the accent border.
    private var rows: some View {
        let items: [(id: String, title: String, detail: String, on: Bool, action: () -> Void)]
        if let c = currentCountry {
            items = c.cities.map { city in
                (city.id, city.name, city.name == self.city ? "pin dropped" : "tap to drop a pin",
                 city.name == self.city, { chooseCity(city.name) })
            }
        } else if let c = currentContinent {
            items = c.countries.map { country in
                (country.id, country.name, "\(country.cities.count) \(country.cities.count == 1 ? "city" : "cities")",
                 false, { set(continent: continent, country: country.name, city: "") })
            }
        } else {
            items = catalog.continents.map { c in
                (c.id, c.name, "\(c.countries.count) countries", false, { chooseContinent(c) })
            }
        }
        let level = "\(continent)|\(country)"
        return ScrollView {
            VStack(spacing: 8) {
                if currentContinent == nil {
                    Text("Drag to spin. Tap a continent, or hold and slide to light one up.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    DestinationRow(title: item.title, detail: item.detail, on: item.on, index: index,
                                   action: item.action)
                }
            }
            .id(level)
        }
        .scrollIndicators(.hidden)
    }

    /// Tapping the continent already chosen keeps the country and city; the chips zoom back out.
    private func chooseContinent(_ c: Continent) {
        guard c.name != continent else { return }
        set(continent: c.name, country: "", city: "")
    }

    private func chooseCity(_ name: String) {
        set(continent: continent, country: country, city: name)
    }

    private func set(continent: String, country: String, city: String) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            self.continent = continent
            self.country = country
            self.city = city
        }
    }
}

private struct Chip: View {
    let title: String
    var systemImage: String?
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Theme.accentInk : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.chip), in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(title)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

/// A row that slides up into place, a little after the one above it.
private struct DestinationRow: View {
    let title: String
    let detail: String
    let on: Bool
    let index: Int
    let action: () -> Void
    @State private var shown = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body)
                Spacer()
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                Image(systemName: on ? "mappin.circle.fill" : "chevron.right")
                    .foregroundStyle(on ? Theme.accent : Theme.secondaryText)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, lineWidth: on ? 2 : 0)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .offset(y: shown ? 0 : 24)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.05)) { shown = true }
        }
    }
}
