///|
extern "C" fn exit_process(code : Int32) -> Unit = "exit"

///|
async fn main {
  @core.run_cli(@env.args()[1:]) catch {
    @core.VcsError::CheckoutFailed(reason) => {
      println("Checkout refused: " + reason)
      exit_process(1)
    }
    @core.VcsError::SwitchIncomplete(reason) => {
      println("SwitchIncomplete: " + reason)
      exit_process(18)
    }
    @core.VcsError::DiffFailed(reason) => {
      println("Diff failed: " + reason)
      exit_process(1)
    }
    @core.VcsError::PolicyRejected(reason) => {
      println("Commit rejected\n" + reason)
      exit_process(2)
    }
    @core.VcsError::PolicyExecutionFailed(reason) => {
      println("Commit stopped: required policy error\n" + reason)
      exit_process(3)
    }
    @core.VcsError::ObjectUnavailableOffline(id) => {
      println("ObjectUnavailableOffline: " + id)
      exit_process(4)
    }
    @core.VcsError::UnknownObject(id) => {
      println("UnknownObject: " + id)
      exit_process(5)
    }
    @core.VcsError::RemoteUnavailable(_) => {
      println("RemoteUnavailable: configured promisor cannot be read")
      exit_process(6)
    }
    @core.VcsError::RemoteObjectMissing(id) => {
      println("RemoteObjectMissing: " + id)
      exit_process(7)
    }
    @core.VcsError::InvalidObject(_) => {
      println(
        "ObjectCorrupt: hash, type or canonical encoding validation failed",
      )
      exit_process(8)
    }
    @core.VcsError::InvalidPromise(_) => {
      println("InvalidPromise: partial-clone metadata verification failed")
      exit_process(9)
    }
    @core.VcsError::RemoteRefChanged(_) => {
      println("RemoteRefChanged: clone snapshot was not published")
      exit_process(10)
    }
    @core.VcsError::RefConflict(_) => {
      println("RefConflict: expected old Ref changed; refresh and retry")
      exit_process(11)
    }
    @core.VcsError::StagingBusy(_) => {
      println("StagingBusy: another staging transaction is active; retry later")
      exit_process(15)
    }
    @core.VcsError::PublicationUncertain(_) => {
      println(
        "PublicationUncertain: data may be published; stop writers, run moonvcs recover --check before retry; see BRANCH_SWITCH.md and docs/RECOVERY.md",
      )
      exit_process(16)
    }
    @core.VcsError::ReceiveRejected(reason) => {
      println("Push rejected\n" + reason)
      exit_process(12)
    }
    @core.VcsError::ReceivePolicyError(reason) => {
      println("Push stopped: required server policy error\n" + reason)
      exit_process(13)
    }
    @core.VcsError::ReceiveInvalid(reason) => {
      println("Push rejected: invalid receive candidate\n" + reason)
      exit_process(14)
    }
    @core.VcsError::ReceiveProcessExit(code) => exit_process(code)
    _ => {
      println("MoonVCS operation failed")
      exit_process(1)
    }
  }
}
