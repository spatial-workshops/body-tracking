import Foundation

// `BodyTracking --detect <image>` runs one detection from the terminal (see CommandLineTool);
// `BodyTracking --check-config` validates bodytracking.yaml; otherwise the SwiftUI app starts.
if CommandLine.arguments.contains("--check-config") {
    exit(CommandLineTool.checkConfiguration(arguments: CommandLine.arguments))
} else if let options = CommandLineTool.Options(arguments: CommandLine.arguments) {
    Task {
        exit(await CommandLineTool.run(options))
    }
    dispatchMain()
} else {
    BodyTrackingApp.main()
}
