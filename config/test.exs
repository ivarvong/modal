import Config

# Use the Mox mock instead of the real gRPC client in unit tests.
# Integration tests start their own Modal.Client and bypass this.
config :modal, client_impl: Modal.Client.Mock
config :modal, tcr_stub: Modal.TaskCommandRouter.Mock
config :modal, wait_retry_delay: 0
config :modal, fs_retry_delay: 0
config :modal, modal_stub: Modal.ModalStub.Mock
