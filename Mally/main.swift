import Dispatch

if SelfTestHarness.isRequested {
    Task { @MainActor in
        await SelfTestHarness.runAndExit()
    }
    dispatchMain()
} else {
    MallyApp.main()
}
