import Flutter
import MapKit
import UIKit

// MARK: - Annotation model

final class MunawwaraMapAnnotation: NSObject, MKAnnotation {
  @objc dynamic var coordinate: CLLocationCoordinate2D
  let markerId: String
  let kind: String
  let tintArgb: Int
  let glyphName: String?

  var title: String?
  var subtitle: String?

  init(
    markerId: String,
    latitude: Double,
    longitude: Double,
    kind: String,
    title: String?,
    subtitle: String?,
    tintArgb: Int,
    glyphName: String?,
  ) {
    self.markerId = markerId
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.tintArgb = tintArgb
    self.glyphName = glyphName
    coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    super.init()
  }
}

// MARK: - Platform view (MKMapView + native clustering)

final class MunawwaraMapPlatformView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let container = UIView()
  private let mapView = MKMapView()
  private let topEdgeBlur: MunawwaraScrollEdgeBlurOverlay
  private let bottomEdgeBlur: MunawwaraScrollEdgeBlurOverlay
  private let channel: FlutterMethodChannel
  private var annotationsById: [String: MunawwaraMapAnnotation] = [:]
  private var suppressRegionEvents = false

  private var topEdgeHeight: CGFloat = 0
  private var bottomEdgeHeight: CGFloat = 0
  private var edgeBlurEnabled = true
  private var topHeightConstraint: NSLayoutConstraint?
  private var bottomHeightConstraint: NSLayoutConstraint?

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any]?,
    messenger: FlutterBinaryMessenger,
  ) {
    let isDark = args?["isDark"] as? Bool ?? false
    topEdgeBlur = MunawwaraScrollEdgeBlurOverlay(fadesFromTop: true, isDark: isDark)
    bottomEdgeBlur = MunawwaraScrollEdgeBlurOverlay(fadesFromTop: false, isDark: isDark)

    channel = FlutterMethodChannel(
      name: "com.munawwaracare/mapkit_\(viewId)",
      binaryMessenger: messenger,
    )
    super.init()

    container.backgroundColor = .clear
    container.clipsToBounds = true

    mapView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(mapView)

    topEdgeBlur.translatesAutoresizingMaskIntoConstraints = false
    bottomEdgeBlur.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(topEdgeBlur)
    container.addSubview(bottomEdgeBlur)

    let topHeight = topEdgeBlur.heightAnchor.constraint(equalToConstant: 0)
    let bottomHeight = bottomEdgeBlur.heightAnchor.constraint(equalToConstant: 0)
    topHeightConstraint = topHeight
    bottomHeightConstraint = bottomHeight

    NSLayoutConstraint.activate([
      mapView.topAnchor.constraint(equalTo: container.topAnchor),
      mapView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      mapView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      mapView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

      topEdgeBlur.topAnchor.constraint(equalTo: container.topAnchor),
      topEdgeBlur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      topEdgeBlur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      topHeight,

      bottomEdgeBlur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      bottomEdgeBlur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      bottomEdgeBlur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      bottomHeight,
    ])

    mapView.delegate = self
    mapView.isScrollEnabled = true
    mapView.isZoomEnabled = true
    mapView.showsCompass = true
    mapView.showsScale = false
    mapView.isRotateEnabled = true
    mapView.isPitchEnabled = false
    mapView.isMultipleTouchEnabled = true
    mapView.pointOfInterestFilter = .excludingAll

    if let showsUser = args?["showsUserLocation"] as? Bool {
      mapView.showsUserLocation = showsUser
    }
    if isDark {
      mapView.overrideUserInterfaceStyle = .dark
    }

    mapView.register(
      MKMarkerAnnotationView.self,
      forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
    )
    mapView.register(
      MKMarkerAnnotationView.self,
      forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
    )

    if let top = args?["edgeBlurTopHeight"] as? Double {
      topEdgeHeight = CGFloat(top)
    }
    if let bottom = args?["edgeBlurBottomHeight"] as? Double {
      bottomEdgeHeight = CGFloat(bottom)
    }
    if let enabled = args?["edgeBlurEnabled"] as? Bool {
      edgeBlurEnabled = enabled
    }
    applyEdgeLayout()

    let lat = args?["latitude"] as? Double ?? 21.3891
    let lng = args?["longitude"] as? Double ?? 39.8579
    let zoom = args?["zoom"] as? Double ?? 15
    let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    let span = Self.span(forZoom: zoom)
    mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func view() -> UIView { container }

  private func applyEdgeLayout() {
    topHeightConstraint?.constant = topEdgeHeight
    bottomHeightConstraint?.constant = bottomEdgeHeight
    topEdgeBlur.isHidden = !edgeBlurEnabled || topEdgeHeight <= 0
    bottomEdgeBlur.isHidden = !edgeBlurEnabled || bottomEdgeHeight <= 0
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "moveCamera":
      guard let args = call.arguments as? [String: Any],
        let lat = args["latitude"] as? Double,
        let lng = args["longitude"] as? Double
      else {
        result(FlutterError(code: "bad_args", message: "moveCamera needs lat/lng", details: nil))
        return
      }
      let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      let preserveZoom = args["preserveZoom"] as? Bool ?? false
      suppressRegionEvents = true
      mapView.userTrackingMode = .none
      if preserveZoom {
        mapView.setCenter(center, animated: false)
      } else {
        let zoom = args["zoom"] as? Double ?? 15
        mapView.setRegion(
          MKCoordinateRegion(center: center, span: Self.span(forZoom: zoom)),
          animated: false,
        )
      }
      ensureMapInteractionEnabled()
      emitRegionChanged(hasGesture: false)
      DispatchQueue.main.async { [weak self] in
        self?.suppressRegionEvents = false
        self?.ensureMapInteractionEnabled()
      }
      result(true)
    case "setMarkers":
      guard let args = call.arguments as? [String: Any],
        let rawMarkers = args["markers"] as? [[String: Any]]
      else {
        result(FlutterError(code: "bad_args", message: "setMarkers needs markers", details: nil))
        return
      }
      applyMarkers(rawMarkers)
      result(true)
    case "restoreGestures":
      ensureMapInteractionEnabled()
      result(true)
    case "setScrollEdges":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "setScrollEdges needs args", details: nil))
        return
      }
      if let top = args["topHeight"] as? Double {
        topEdgeHeight = CGFloat(max(0, top))
      }
      if let bottom = args["bottomHeight"] as? Double {
        bottomEdgeHeight = CGFloat(max(0, bottom))
      }
      if let enabled = args["enabled"] as? Bool {
        edgeBlurEnabled = enabled
      }
      applyEdgeLayout()
      result(true)
    case "setAppearance":
      guard let args = call.arguments as? [String: Any],
        let isDark = args["isDark"] as? Bool
      else {
        result(FlutterError(code: "bad_args", message: "setAppearance needs isDark", details: nil))
        return
      }
      topEdgeBlur.setDarkMode(isDark)
      bottomEdgeBlur.setDarkMode(isDark)
      mapView.overrideUserInterfaceStyle = isDark ? .dark : .unspecified
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyMarkers(_ raw: [[String: Any]]) {
    var incomingIds = Set<String>()

    for item in raw {
      guard let id = item["id"] as? String,
        let lat = item["latitude"] as? Double,
        let lng = item["longitude"] as? Double
      else { continue }

      incomingIds.insert(id)

      if let existing = annotationsById[id] {
        let next = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        if existing.coordinate.latitude != next.latitude
          || existing.coordinate.longitude != next.longitude
        {
          existing.coordinate = next
        }
        existing.title = item["title"] as? String
        existing.subtitle = item["subtitle"] as? String
        continue
      }

      let annotation = MunawwaraMapAnnotation(
        markerId: id,
        latitude: lat,
        longitude: lng,
        kind: item["kind"] as? String ?? "default",
        title: item["title"] as? String,
        subtitle: item["subtitle"] as? String,
        tintArgb: item["tintArgb"] as? Int ?? 0xFF2E7D32,
        glyphName: item["glyphName"] as? String,
      )
      annotationsById[id] = annotation
      mapView.addAnnotation(annotation)
    }

    let staleIds = annotationsById.keys.filter { !incomingIds.contains($0) }
    for id in staleIds {
      if let annotation = annotationsById.removeValue(forKey: id) {
        mapView.removeAnnotation(annotation)
      }
    }
  }

  private static func span(forZoom zoom: Double) -> MKCoordinateSpan {
    let delta = 360 / pow(2, zoom)
    return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
  }

  private func emitRegionChanged(hasGesture: Bool) {
    channel.invokeMethod(
      "onRegionChanged",
      arguments: [
        "latitude": mapView.centerCoordinate.latitude,
        "longitude": mapView.centerCoordinate.longitude,
        "hasGesture": hasGesture,
      ],
    )
  }

  /// MKMapView scroll gestures can stall after programmatic camera moves or
  /// when an iOS back-swipe is cancelled mid-gesture over the platform view.
  private func ensureMapInteractionEnabled() {
    mapView.isUserInteractionEnabled = true
    mapView.isScrollEnabled = true
    mapView.isZoomEnabled = true
    mapView.isRotateEnabled = true
    for recognizer in mapView.gestureRecognizers ?? [] {
      recognizer.isEnabled = true
    }
    for subview in mapView.subviews {
      subview.isUserInteractionEnabled = true
      for recognizer in subview.gestureRecognizers ?? [] {
        recognizer.isEnabled = true
      }
    }
  }

  private static func color(from argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255
    let r = CGFloat((argb >> 16) & 0xFF) / 255
    let g = CGFloat((argb >> 8) & 0xFF) / 255
    let b = CGFloat(argb & 0xFF) / 255
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }

  private static func glyphImage(name: String?) -> UIImage? {
    guard let name, !name.isEmpty else { return nil }
    let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
    return UIImage(systemName: name, withConfiguration: config)
  }

  // MARK: MKMapViewDelegate

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    if annotation is MKUserLocation { return nil }

    if let cluster = annotation as? MKClusterAnnotation {
      let view = mapView.dequeueReusableAnnotationView(
        withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
        for: cluster,
      ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
        annotation: cluster,
        reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
      )
      view.markerTintColor = UIColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)
      view.glyphText = "\(cluster.memberAnnotations.count)"
      view.clusteringIdentifier = "munawwara"
      return view
    }

    guard let custom = annotation as? MunawwaraMapAnnotation else { return nil }

    let view = mapView.dequeueReusableAnnotationView(
      withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
      for: custom,
    ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
      annotation: custom,
      reuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
    )
    view.annotation = custom
    view.canShowCallout = custom.title != nil
    view.markerTintColor = Self.color(from: custom.tintArgb)
    view.clusteringIdentifier = "munawwara"
    if let glyph = Self.glyphImage(name: custom.glyphName) {
      view.glyphImage = glyph
    } else if custom.kind == "pilgrim" {
      view.glyphImage = Self.glyphImage(name: "person.fill")
    }
    return view
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let custom = view.annotation as? MunawwaraMapAnnotation else { return }
    channel.invokeMethod("onMarkerTap", arguments: ["id": custom.markerId])
    mapView.deselectAnnotation(custom, animated: false)
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    if suppressRegionEvents { return }
    emitRegionChanged(hasGesture: true)
  }
}

// MARK: - Factory

final class MunawwaraMapViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
  ) -> FlutterPlatformView {
    let params = args as? [String: Any]
    return MunawwaraMapPlatformView(
      frame: frame,
      viewId: viewId,
      args: params,
      messenger: messenger,
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

// MARK: - Plugin registration

enum MapKitBridge {
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = MunawwaraMapViewFactory(messenger: registrar.messenger())
    registrar.register(
      factory,
      withId: "MunawwaraMapKit",
      gestureRecognizersBlockingPolicy:
        FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded,
    )
  }
}
