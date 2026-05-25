ExUnit.start(exclude: [:integration, :contract])
Mox.defmock(Modal.Client.Mock, for: Modal.Client.Behaviour)
Mox.defmock(Modal.TaskCommandRouter.Mock, for: Modal.TaskCommandRouter.Behaviour)
Mox.defmock(Modal.ModalStub.Mock, for: Modal.ModalStub.Behaviour)
