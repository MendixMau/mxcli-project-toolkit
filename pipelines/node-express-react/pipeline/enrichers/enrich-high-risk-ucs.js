'use strict';

/**
 * Enrich high-risk pending UCs (UPDATE, DELETE, sensitive operations).
 * These operations need explicit business logic before MDL writing.
 */

const fs = require('fs');
const path = require('path');

const knowledgeBaseDir = process.argv[2];
const brdDir = path.join(knowledgeBaseDir, 'brd');

const highRiskEnrichment = {
  'UC-USER-06': {
    // PATCH /users/:userId - update user profile
    actors: ['Authenticated User'],
    preconditions: [
      'User is authenticated',
      'User is updating their own profile OR user is admin',
    ],
    mainFlow: [
      'User navigates to user settings',
      'User edits profile fields (first name, last name, email, phone, avatar)',
      'User clicks save',
      'System validates input (email format, required fields)',
      'System updates user record in database',
      'System returns updated user object',
      'Success message shown',
    ],
    postconditions: [
      'User profile updated in database',
      'Changes visible across app immediately',
      'Other users see updated avatar/public info',
    ],
    openQuestions: [
      'Can user change their own username? (Likely no)',
      'Can user change email to one already in use? (Likely no)',
      'Are there role-based restrictions? (e.g., admin can edit anyone, user can only edit self)',
      'Should change audit trail be logged?',
    ],
  },
  'UC-CONTACT-03': {
    // DELETE /:contactId - delete contact
    actors: ['Authenticated User'],
    preconditions: [
      'User is authenticated',
      'Contact exists',
      'User is the contact owner',
    ],
    mainFlow: [
      'User navigates to contacts list',
      'User clicks delete on a contact',
      'User confirms deletion dialog',
      'System removes contact from database',
      'Contact list refreshed',
    ],
    postconditions: [
      'Contact deleted from database (hard delete)',
      'Contact no longer appears in contact lists',
      'Historical transactions with this contact are NOT deleted',
      'User can re-add contact if needed',
    ],
    openQuestions: [
      'Hard delete or soft delete? (Likely hard — contact is not sensitive data)',
      'Should there be a confirmation dialog?',
      'Should deletion be logged for audit?',
      'Can contact be deleted if they have pending transactions? (Likely yes — does not affect balance)',
    ],
  },
  'UC-NOTIFICATION-03': {
    // PATCH /:notificationId - mark notification as read
    actors: ['Authenticated User'],
    preconditions: [
      'User is authenticated',
      'Notification exists and belongs to user',
      'Notification is unread',
    ],
    mainFlow: [
      'User opens notification center',
      'User clicks on a notification (or mark as read button)',
      'System updates notification status from unread to read',
      'System updates read_at timestamp',
      'Notification removed from unread badge count',
    ],
    postconditions: [
      'Notification marked as read in database',
      'read_at timestamp recorded',
      'Unread count decremented',
      'Notification still visible in history',
    ],
    openQuestions: [
      'Can user bulk-mark notifications as read?',
      'Can user delete notifications?',
      'Should read notifications auto-expire/archive?',
      'What\'s the retention policy?',
    ],
  },
  'UC-BANKTRANSFER-01': {
    // GET / - list bank transfers (low risk per keyword, but complex domain)
    actors: ['Authenticated User'],
    preconditions: [
      'User is authenticated',
      'User has bank accounts configured',
    ],
    mainFlow: [
      'User navigates to bank transfers section',
      'System queries pending transfers for user\'s bank accounts',
      'Transfers displayed with status (pending, completed, failed)',
      'User can view transfer details',
    ],
    postconditions: [
      'Bank transfer list rendered',
      'Status visible for each transfer',
    ],
    openQuestions: [
      'Is this a real external bank integration or placeholder?',
      'What system initiates transfers? (User-triggered, scheduled, webhook-driven?)',
      'What are the possible transfer statuses? (pending, processing, completed, failed, cancelled)',
      'Are transfers synchronous or asynchronous?',
      'What happens on failure? (Retry? Notification? Manual review?)',
      'Is there an audit trail / transaction log?',
    ],
  },
};

let enrichedCount = 0;

// Apply enrichment
for (const [ucId, enrichment] of Object.entries(highRiskEnrichment)) {
  // Find which BRD file contains this UC
  for (const f of fs.readdirSync(brdDir).filter(f => f.endsWith('.brd.json'))) {
    const brdPath = path.join(brdDir, f);
    try {
      const brd = JSON.parse(fs.readFileSync(brdPath, 'utf8'));

      if (brd.useCases) {
        for (const uc of brd.useCases) {
          if (uc.id === ucId) {
            Object.assign(uc, enrichment, {
              reviewStatus: 'enriched',
            });
            enrichedCount++;
            console.log(`  ✓ ${ucId}: enriched`);
            break;
          }
        }
      }

      // Write back if modified
      fs.writeFileSync(brdPath, JSON.stringify(brd, null, 2), 'utf8');
    } catch (e) {
      console.error(`Error processing ${f}: ${e.message}`);
    }
  }
}

console.log(`✓ Enriched ${enrichedCount} high-risk UCs.`);
