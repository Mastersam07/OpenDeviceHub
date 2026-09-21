import UIKit

/// A deliberately plain app used by the verification scripts. It reports the orientation it is in
/// and echoes taps, so a script can read the device's state from a screenshot instead of guessing.
final class ViewController: UIViewController {
    private let orientationLabel = UILabel()
    private let tapLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemIndigo

        orientationLabel.textColor = .white
        orientationLabel.font = .boldSystemFont(ofSize: 44)
        orientationLabel.textAlignment = .center
        tapLabel.textColor = .white
        tapLabel.font = .systemFont(ofSize: 26)
        tapLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [orientationLabel, tapLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
        ])
        update()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The window scene is not attached during viewDidLoad, so the first reading happens here.
        update()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        update()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.update() }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: view) else { return }
        let x = point.x / view.bounds.width
        let y = point.y / view.bounds.height
        let line = String(format: "TAP %.4f %.4f", x, y)
        tapLabel.text = line
        record(line)
    }

    /// Taps and the current orientation are written into the app's Documents directory, so a
    /// verification script can read what the device actually received instead of comparing
    /// screenshots, which is what made the earlier checks fragile.
    private func record(_ line: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let file = directory.appendingPathComponent("events.txt")
        let text = line + "\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func update() {
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .unknown
        let name = switch orientation {
        case .portrait: "PORTRAIT"
        case .portraitUpsideDown: "UPSIDEDOWN"
        case .landscapeLeft: "LANDSCAPELEFT"
        case .landscapeRight: "LANDSCAPERIGHT"
        default: "UNKNOWN"
        }
        orientationLabel.text = name
        record("ORIENTATION \(name)")
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
