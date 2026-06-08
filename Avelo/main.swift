import Dispatch

if SelfTestHarness.isRequested {
    Task { @MainActor in
        await SelfTestHarness.runAndExit()
    }
    dispatchMain()
} else {
    AveloApp.main()
}
