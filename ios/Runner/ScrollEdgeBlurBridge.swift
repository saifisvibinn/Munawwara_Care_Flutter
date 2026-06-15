import Flutter
import UIKit

// MARK: - Shared native scroll-edge glass (UIVisualEffectView)

/// Fades a system blur band at the top or bottom — matches MapKit edge bands.
final class MunawwaraScrollEdgeBlurOverlay: UIView {
  private let effectView: UIVisualEffectView
  private let maskLayer = CAGradientLayer()
  private let fadesFromTop: Bool

  init(fadesFromTop: Bool, isDark: Bool) {
    self.fadesFromTop = fadesFromTop
    effectView = UIVisualEffectView(effect: Self.blurEffect(isDark: isDark))
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    clipsToBounds = true

    effectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effectView)
    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
    maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
    updateMask()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func blurEffect(isDark: Bool) -> UIBlurEffect {
    let style: UIBlurEffect.Style =
      isDark ? .systemThinMaterialDark : .systemUltraThinMaterialLight
    return UIBlurEffect(style: style)
  }

  func setDarkMode(_ isDark: Bool) {
    effectView.effect = Self.blurEffect(isDark: isDark)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    maskLayer.frame = bounds
  }

  private func updateMask() {
    if fadesFromTop {
      maskLayer.colors = [
        UIColor.white.cgColor,
        UIColor.white.withAlphaComponent(0.55).cgColor,
        UIColor.clear.cgColor,
      ]
      maskLayer.locations = [0.0, 0.35, 1.0]
    } else {
      maskLayer.colors = [
        UIColor.clear.cgColor,
        UIColor.white.withAlphaComponent(0.55).cgColor,
        UIColor.white.cgColor,
      ]
      maskLayer.locations = [0.0, 0.65, 1.0]
    }
    layer.mask = maskLayer
  }
}

// MARK: - Standalone platform view for Flutter scroll overlays

final class MunawwaraScrollEdgeBlurPlatformView: NSObject, FlutterPlatformView {
  private let blurOverlay: MunawwaraScrollEdgeBlurOverlay

  init(frame: CGRect, args: [String: Any]?) {
    let isDark = args?["isDark"] as? Bool ?? false
    let fadesFromTop = args?["fadesFromTop"] as? Bool ?? true
    blurOverlay = MunawwaraScrollEdgeBlurOverlay(
      fadesFromTop: fadesFromTop,
      isDark: isDark,
    )
    blurOverlay.frame = frame
    blurOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    super.init()
  }

  func view() -> UIView {
    blurOverlay
  }
}

final class MunawwaraScrollEdgeBlurViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
  ) -> FlutterPlatformView {
    MunawwaraScrollEdgeBlurPlatformView(
      frame: frame,
      args: args as? [String: Any],
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

enum ScrollEdgeBlurBridge {
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = MunawwaraScrollEdgeBlurViewFactory()
    registrar.register(
      factory,
      withId: "MunawwaraScrollEdgeBlur",
      gestureRecognizersBlockingPolicy:
        FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded,
    )
  }
}
