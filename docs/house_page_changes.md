# HousePage / Agenda — Changes (2026-01-07)

Summary
- Replaced the old `HousePage` view with an improved daily agenda (Doctolib-like) showing timeline blocks for slots across all queues.
- Implemented compact display rules for slots (single capacity shows client's formatted name, multi-capacity shows counts).
- Added overlap handling (interval partitioning -> columns) to lay out overlapping slots.
- Added interactions: slot details dialog, status toggle (open/blocked), delete with notifications, and "Nouveau RDV" quick-create.
- Implemented Option C: client search in the quick-create dialog (search by name/email, select to autofill).
- Added UI polish: responsive px-per-minute, left color stripe, improved touch targets, tooltip, and accessibility semantics.

Technical notes
- File modified: `lib/page b-acceuil/company/house_page.dart`.
- Firestore collections used:
  - `companies/{companyId}/queues/{queueId}/slots`
  - `companies/{companyId}/reservations`
  - `users` (for client search / display name lookup)
  - `customers/{customerId}/notifications` (for cancellation notices)
- Reservation creation is done in a Firestore transaction to increment `slot.reserved` atomically and create a `reservations` document.
- Notifications scheduled via `NotificationService` (existing project service).

Testing & TODOs
- Manual test steps added to the PR description (see below).
- Remaining tasks: visual tweaks, responsive fine-tuning, unit/integration tests (not implemented yet).

Manual test checklist
1. Open `HousePage` and pick a date with slots.
2. Verify timeline renders from 08:00 to 18:00 and slots are positioned/height-correct.
3. Select a slot:
   - Open details, check client names for single-capacity slots and list for multi-capacity.
   - Use "Nouveau RDV", search existing client by name/email, select and create a reservation.
   - Verify reservation appears and counts update.
4. Toggle slot status (open/blocked) and verify Firestore updates and UI refresh.
5. Delete a slot and confirm notifications are written into `customers/{id}/notifications` for affected clients.

If anything in this document looks off, tell me which part you want adjusted and I will update it.