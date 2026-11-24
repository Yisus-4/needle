import Foundation

@main
struct NeedleCoreTestsMain {
    static func main() async {
        let runner = TestRunner()
        registerLRCParserTests(runner)
        registerPlaybackClockTests(runner)
        registerLRCLIBClientTests(runner)

        let filter = CommandLine.arguments.dropFirst().first
        let code = await runner.execute(filter: filter)
        exit(code)
    }
}
