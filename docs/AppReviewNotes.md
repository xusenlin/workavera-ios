# App Review Notes

Use the following text in the App Review Notes field in App Store Connect.
Enter the live review server address and demo credentials in App Store Connect;
do not commit credentials to this repository.

## Account access

Workavera does not offer account registration or automatic account creation. It
is a client for self-hosted Workavera servers. User accounts are provisioned and
managed by the administrator of each server.

The credentials provided in App Review Information grant access to a fully
configured review account. On the sign-in screen, use **Server Settings** to
confirm the supplied review server address, then sign in with the supplied email
address and password.

The review server will remain publicly reachable and fully operational throughout
the review period.

## Account and data management

The iOS app does not create accounts. Account lifecycle and deletion requests are
handled by the administrator of the self-hosted server selected by the user. The
app developer does not operate a central account or content database and cannot
access or delete data on independently operated servers.

## AI features

AI requests are routed through the selected Workavera server to the model
configuration chosen by the signed-in user. Before data is sent to a model for
the first time, the app displays the model provider and asks for explicit
permission. Consent is stored locally for that user and model configuration.
