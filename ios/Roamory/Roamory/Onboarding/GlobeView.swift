import RoamoryKit
import SceneKit
import SwiftUI

/// The destination globe (TRD §3.2): spins until touched, drags with inertia, swoops to the focus, lights the
/// continent under a held finger, and drops pulsing city pins.
struct GlobeView: UIViewRepresentable {
    /// Camera distances from the center of the unit globe: the whole globe, and the closest zoom.
    static let worldDistance = 3.2
    static let closestDistance = 1.6
    /// Vertical, in degrees. The view is square, so it is the horizontal one too.
    static let fieldOfView = 38.0

    let catalog: OnboardingCatalog
    /// Continent id to light up.
    var focusedContinent: String?
    /// Where the camera looks; nil keeps the globe spinning.
    var focus: GeoPoint?
    /// Camera distance from the globe's center, between `closestDistance` and `worldDistance`.
    var distance: Double
    var pins: [City]
    var selectedPin: String?
    var onTapContinent: (Continent) -> Void
    var onTapPin: (City) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(catalog: catalog) }

    func makeUIView(context: Context) -> SCNView { context.coordinator.view }

    func updateUIView(_ uiView: SCNView, context: Context) { context.coordinator.update(self) }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let view = SCNView()
        private let catalog: OnboardingCatalog
        private var parent: GlobeView?
        private let globe = SCNNode()
        private let surface = SCNNode(geometry: SCNSphere(radius: 1))
        private let camera = SCNNode()
        private var pinNodes: [String: SCNNode] = [:]
        private var link: CADisplayLink?
        private var lastTick: CFTimeInterval = 0

        // Orientation, in radians: yaw = −longitude and pitch = latitude of the point facing the camera.
        private var yaw = -2.0
        private var pitch = 0.3
        private var distance = GlobeView.worldDistance
        private var target: (yaw: Double, pitch: Double, distance: Double)?
        private var velocity = CGVector.zero
        private var dragging = false
        private var spinning = true

        private var litContinent: String??
        private var hover: String?
        /// Where a hold began; letting go only chooses if the finger stayed put.
        private var holdStart: CGPoint?
        private var focusKey: String?
        private var pinKey: [String] = []
        private var selectedPin: String?
        private let scrubHaptic = UISelectionFeedbackGenerator()

        private static let maxPitch = Double.pi / 3

        init(catalog: OnboardingCatalog) {
            self.catalog = catalog
            super.init()
            let scene = SCNScene()
            let material = surface.geometry!.firstMaterial!
            material.lightingModel = .lambert
            material.emission.intensity = 0.3
            (surface.geometry as? SCNSphere)?.segmentCount = 96
            globe.addChildNode(surface)
            scene.rootNode.addChildNode(globe)

            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = GlobeView.fieldOfView
            // The default near plane (1) clips the globe once the camera is closer than 2 from its center.
            camera.camera?.zNear = 0.01
            camera.position = SCNVector3(0, 0, Float(distance))
            scene.rootNode.addChildNode(camera)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .omni
            key.light?.intensity = 1100
            key.position = SCNVector3(-4, 3, 5)
            scene.rootNode.addChildNode(key)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 250
            scene.rootNode.addChildNode(ambient)

            view.scene = scene
            view.pointOfView = camera
            view.backgroundColor = .clear
            view.isOpaque = false
            view.antialiasingMode = .multisampling4X
            view.rendersContinuously = true

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold))
            hold.minimumPressDuration = 0.2
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            pan.require(toFail: hold)
            tap.require(toFail: pan)
            [pan, hold, tap].forEach(view.addGestureRecognizer)

            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
            apply()
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        func update(_ globeView: GlobeView) {
            parent = globeView
            renderTexture()

            let key = globeView.focus.map { "\($0.lat),\($0.lon),\(globeView.distance)" } ?? "none,\(globeView.distance)"
            if key != focusKey {
                focusKey = key
                velocity = .zero
                if let focus = globeView.focus {
                    spinning = false
                    let wanted = -focus.lon * .pi / 180
                    target = (yaw: yaw + Self.wrap(wanted - yaw),
                              pitch: min(max(focus.lat * .pi / 180, -Self.maxPitch), Self.maxPitch),
                              distance: globeView.distance)
                } else {
                    spinning = true
                    target = (yaw: yaw, pitch: 0.3, distance: globeView.distance)
                }
            }

            let ids = globeView.pins.map(\.id)
            if ids != pinKey {
                pinKey = ids
                replacePins(globeView.pins)
                selectedPin = nil
            }
            if globeView.selectedPin != selectedPin {
                selectedPin = globeView.selectedPin
                styleSelectedPin()
            }
        }

        // MARK: Drawing

        private func renderTexture() {
            let lit = hover ?? parent?.focusedContinent
            guard litContinent != .some(lit) else { return }
            litContinent = .some(lit)
            let image = GlobeTexture.image(catalog: catalog, highlighted: lit)
            let material = surface.geometry!.firstMaterial!
            material.diffuse.contents = image
            material.emission.contents = image
        }

        private func replacePins(_ cities: [City]) {
            for node in pinNodes.values {
                node.runAction(.sequence([.scale(to: 0, duration: 0.2), .removeFromParentNode()]))
            }
            pinNodes = [:]
            for (i, city) in cities.enumerated() {
                let node = Self.makePin()
                let normal = SIMD3<Float>(GeoMath.unitVector(city.location))
                node.simdOrientation = simd_quatf(from: [0, 1, 0], to: normal)
                node.simdPosition = normal * 1.25
                node.scale = SCNVector3(0, 0, 0)
                globe.addChildNode(node)
                let drop = SCNAction.group([.move(to: SCNVector3(normal * 1.0), duration: 0.45),
                                            .scale(to: 1, duration: 0.35)])
                drop.timingMode = .easeOut
                node.runAction(.sequence([.wait(duration: 0.25 + Double(i) * 0.08), drop]))
                pinNodes[city.id] = node
            }
        }

        /// A stalk, a head, and a flat pulse ring that runs only while the pin is selected.
        private static func makePin() -> SCNNode {
            let pin = SCNNode()
            let stalk = SCNNode(geometry: SCNCylinder(radius: 0.003, height: 0.04))
            stalk.position = SCNVector3(0, 0.02, 0)
            stalk.geometry?.firstMaterial?.lightingModel = .constant
            stalk.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
            let head = SCNNode(geometry: SCNSphere(radius: 0.014))
            head.name = "head"
            head.position = SCNVector3(0, 0.045, 0)
            head.geometry?.firstMaterial?.lightingModel = .constant
            head.geometry?.firstMaterial?.diffuse.contents = UIColor(Theme.accent2)
            let ring = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 0.001))
            ring.name = "ring"
            ring.position = SCNVector3(0, 0.002, 0)
            ring.geometry?.firstMaterial?.lightingModel = .constant
            ring.geometry?.firstMaterial?.diffuse.contents = UIColor(Theme.accent)
            ring.opacity = 0
            [stalk, head, ring].forEach(pin.addChildNode)
            return pin
        }

        private func styleSelectedPin() {
            for (id, pin) in pinNodes {
                let isSelected = id == selectedPin
                let head = pin.childNode(withName: "head", recursively: false)
                let ring = pin.childNode(withName: "ring", recursively: false)
                head?.geometry?.firstMaterial?.diffuse.contents = UIColor(isSelected ? Theme.accent : Theme.accent2)
                head?.runAction(.scale(to: isSelected ? 1.5 : 1, duration: 0.25))
                ring?.removeAllActions()
                ring?.opacity = 0
                if isSelected {
                    let pulse = SCNAction.sequence([
                        .group([.scale(to: 1, duration: 0), .fadeOpacity(to: 0.8, duration: 0)]),
                        .group([.scale(to: 3.2, duration: 1.2), .fadeOpacity(to: 0, duration: 1.2)]),
                    ])
                    ring?.runAction(.repeatForever(pulse))
                }
            }
        }

        // MARK: Motion

        @objc private func tick(_ link: CADisplayLink) {
            let dt = lastTick == 0 ? 1.0 / 60 : min(link.timestamp - lastTick, 0.1)
            lastTick = link.timestamp
            if let t = target {
                let k = 1 - exp(-dt * 4.5)
                yaw += (t.yaw - yaw) * k
                pitch += (t.pitch - pitch) * k
                distance += (t.distance - distance) * k
                if abs(t.yaw - yaw) + abs(t.pitch - pitch) + abs(t.distance - distance) < 0.0005 { target = nil }
            } else if !dragging, velocity != .zero {
                yaw += velocity.dx * dt
                pitch = min(max(pitch + velocity.dy * dt, -Self.maxPitch), Self.maxPitch)
                let decay = exp(-dt * 2.5)
                velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
                if abs(velocity.dx) + abs(velocity.dy) < 0.01 { velocity = .zero }
            } else if !dragging, spinning {
                yaw += 0.16 * dt
            }
            apply()
        }

        private func apply() {
            globe.simdOrientation = simd_quatf(angle: Float(pitch), axis: [1, 0, 0])
                * simd_quatf(angle: Float(yaw), axis: [0, 1, 0])
            camera.position = SCNVector3(0, 0, Float(distance))
        }

        /// Radians of turn per point of drag, so the surface roughly follows the finger at any zoom.
        private var radiansPerPoint: Double {
            let radiusOnScreen = Double(max(view.bounds.width, 1)) * 0.42 * GlobeView.worldDistance / distance
            return 1 / radiusOnScreen
        }

        // MARK: Gestures

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                dragging = true
                target = nil
                velocity = .zero
            case .changed:
                let d = pan.translation(in: view)
                pan.setTranslation(.zero, in: view)
                yaw += d.x * radiansPerPoint
                pitch = min(max(pitch + d.y * radiansPerPoint, -Self.maxPitch), Self.maxPitch)
            default:
                dragging = false
                let v = pan.velocity(in: view)
                velocity = CGVector(dx: v.x * radiansPerPoint, dy: v.y * radiansPerPoint)
            }
        }

        /// Hold and slide: the continent under the finger lights up. Letting go where the hold began acts like a tap
        /// (a slow tap); letting go elsewhere only ends the preview, so a held drag never chooses.
        @objc private func handleHold(_ hold: UILongPressGestureRecognizer) {
            let point = hold.location(in: view)
            let continent = continent(at: point)
            switch hold.state {
            case .began, .changed:
                if hold.state == .began { holdStart = point }
                dragging = true
                if continent?.id != hover {
                    hover = continent?.id
                    if hover != nil { scrubHaptic.selectionChanged() }
                    renderTexture()
                }
            case .ended:
                dragging = false
                hover = nil
                renderTexture()
                let start = holdStart ?? point
                holdStart = nil
                guard hypot(point.x - start.x, point.y - start.y) < 10 else { return }
                if let city = pin(near: point) {
                    parent?.onTapPin(city)
                } else if let continent {
                    parent?.onTapContinent(continent)
                }
            default:
                dragging = false
                hover = nil
                holdStart = nil
                renderTexture()
            }
        }

        @objc private func handleTap(_ tap: UITapGestureRecognizer) {
            let point = tap.location(in: view)
            if let city = pin(near: point) {
                parent?.onTapPin(city)
            } else if let continent = continent(at: point) {
                parent?.onTapContinent(continent)
            }
        }

        private func continent(at point: CGPoint) -> Continent? {
            let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            guard let hit = hits.first(where: { $0.node === surface }) else { return nil }
            let local = globe.simdConvertPosition(SIMD3<Float>(hit.worldCoordinates), from: nil)
            return catalog.continent(at: GeoMath.geoPoint(SIMD3<Double>(local)))
        }

        /// The front-facing pin within a finger's width of `point`.
        private func pin(near point: CGPoint) -> City? {
            guard let cities = parent?.pins else { return nil }
            var best: (City, CGFloat)?
            for city in cities {
                guard let node = pinNodes[city.id], let head = node.childNode(withName: "head", recursively: false)
                else { continue }
                let world = head.simdWorldPosition
                guard simd_dot(simd_normalize(world), [0, 0, 1]) > 0.2 else { continue }
                let projected = view.projectPoint(SCNVector3(world))
                let d = hypot(CGFloat(projected.x) - point.x, CGFloat(projected.y) - point.y)
                if d < 30, d < (best?.1 ?? .infinity) { best = (city, d) }
            }
            return best?.0
        }

        /// `angle` folded into (−π, π].
        private static func wrap(_ angle: Double) -> Double {
            var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
            if a > .pi { a -= 2 * .pi }
            if a <= -.pi { a += 2 * .pi }
            return a
        }
    }
}
