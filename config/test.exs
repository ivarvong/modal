import Config

# Use the Mox mock instead of the real gRPC client in unit tests.
# Integration tests start their own Modal.Client and bypass this.
config :modal, client_impl: Modal.Client.Mock
config :modal, wait_retry_delay: 0
config :modal, fs_retry_delay: 0
# Zero in test so retry tests don't actually sleep — Modal.Backoff
# short-circuits to 0ms when base_ms is 0.
config :modal, rpc_retry_base_ms: 0
