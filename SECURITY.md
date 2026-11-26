# Security

Report security issues privately to Lada Bilak at lada.bilak1@gmail.com. Include the macOS version, KeyOops commit, application, and a minimal reproduction using invented text. Omit passwords, private messages and real clipboard contents.

KeyOops processes selections on demand in memory. A Service request contains text supplied by the calling application. The provider checks macOS secure input before reading the selection and again after confirmation. Protected fields also depend on the host withholding its contents. A host that deliberately supplies sensitive text cannot be identified reliably from the Service request.

Changes that expand input access, retention or permissions should explain the need, the lifetime of the data and how cancellation or failure affects the host selection.
