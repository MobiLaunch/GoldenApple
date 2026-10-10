# Golden Gate Mail — signed-in workspace redesign

## What changed

The old Mail view placed the inbox and message reader **under the title
toolbar** by enabling `fullSizeContent`. Its list and composer also used
fixed heights that broke at narrow window sizes.

The new Mail workspace follows Apple's sidebar/split-view conventions:

- **Mailboxes sidebar:** compact, grouped favorites and account identity.
  Inbox shows the actual unread count; Drafts shows the existing locally
  auto-saved draft. The sidebar may be hidden from the toolbar.
- **Message list:** a distinct surface with sender initials, emphasized
  unread messages, meaningful dates, selected-row highlighting, text
  filtering, All/Unread choice, and accessible keyboard selection.
- **Reader:** a dedicated pane with a clear subject, sender identity,
  recipients, date, plain-text body, and real Reply/Forward actions.
- **Adjustable split:** users can drag the narrow list/reader divider.
- **Compact layouts:** below 700 px of actual available content width the
  list and reader use one pane at a time, and a Back control returns to Inbox.
  The selected message and row state remain consistent during refreshes.
- **Composer:** full-height editing area, aligned To/Subject rows,
  plain-text editor with Writing Tools, saved drafts and Send controls
  pinned safely inside the window.
- **Account setup:** the form now scrolls when the window is too short.
  A previously saved draft does not forcibly open the composer at startup.
- **Errors:** a failed message read offers a retry and does not trap the
  reader in a loading state.

The working IMAP/SMTP connection, keyring credentials, draft autosave,
and send flow have **not** been replaced.

## Faster inbox loading

The prior IMAP client issued up to 80 sequential UID FETCH commands to
read message headers after login. It now fetches recent messages in
groups of 25, with UID-verified parsing and individual fallbacks for
providers that reject UID sets.

In particular, it does not rely on the server response order: every
message is associated with the explicit UID from its FETCH metadata.

## Functional scope

This release provides a working **Inbox** and a **single local draft**.
The backend does not yet provide IMAP synchronization for Sent, Archive,
Junk, or Trash, so the UI intentionally does not show fake mailboxes that
cannot open. Search filters the most recent 80 loaded inbox messages;
full remote-server search will require an additional backend action.
Message reading is currently plain text, rather than a complete HTML
email renderer. Email attachments are a separate future feature.

## Validation

- `python tests/mail-layout.py`: fake IMAP UID batches, out-of-order
  responses, unread flags, legacy-server fallback, responsive geometry,
  sidebar navigation, composing and drafts.
- `python tests/mail-connect.py`: live local IMAP/SMTP account-setup tests.
- `python tests/mail-drafts.py`: draft persistence and private permissions.
- `python tests/qml-load.py`: renders **logged-in** inbox, reading,
  compact reading, composer and drafts states using explicit fixtures,
  in addition to the logged-out Mail launch.

Reference guidance:

- [Apple HIG: Split Views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [Apple HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple HIG: Search Fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)

Hardware confirmation on a real Golden Gate desktop is still needed
for HiDPI rendering, actual focus/keyboard behavior, remote IMAP
provider variations, and Linux compositor blur/translucency.
