import Foundation

// `BodyTracking --detect <image>` runs one detection from the terminal (see CommandLineTool);
// otherwise the SwiftUI app starts.
if let options = CommandLineTool.Options(arguments: CommandLine.arguments) {
    Task {
        exit(await CommandLineTool.run(options))
    }
    dispatchMain()
} else {
    BodyTrackingApp.main()
}
