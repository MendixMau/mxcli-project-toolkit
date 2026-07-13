'use strict';

/**
 * Manual first-pass use case enrichment based on domain knowledge + README.
 * Fills in the TODO fields for scaffolds with reasonable inferred values.
 *
 * Covers:
 * - Actors (who uses this feature?)
 * - Preconditions (what must be true?)
 * - Postconditions (what state changed?)
 * - Main flow (specific ordered steps)
 *
 * Usage: node manual-enrich-usecases.js <knowledgeBaseDir>
 */

const fs = require('fs');
const path = require('path');

const knowledgeBaseDir = process.argv[2];

if (!knowledgeBaseDir) {
  console.error('Usage: node manual-enrich-usecases.js <knowledgeBaseDir>');
  process.exit(1);
}

const brdDir = path.join(knowledgeBaseDir, 'brd');

const enrichmentRules = {
  // Transaction module
  'UC-TRANSACTION-01': {
    // User creates transaction → Payment
    actors: ['Payer/Sender'],
    preconditions: ['User is authenticated', 'User has sufficient balance', 'Recipient exists and is a contact'],
    mainFlow: [
      'User navigates to new transaction',
      'User selects recipient from contacts',
      'User enters amount and description',
      'User confirms payment',
      'System deducts amount from payer balance',
      'System credits amount to recipient balance',
      'System records transaction in database',
      'Success confirmation shown to user',
    ],
    postconditions: [
      'Transaction created with status PENDING',
      'Payer balance reduced by amount',
      'Recipient balance increased by amount',
      'Notification sent to recipient',
      'Transaction visible in both users\' feeds',
    ],
  },
  'UC-TRANSACTION-02': {
    // User creates transaction → Request
    actors: ['Requester'],
    preconditions: ['User is authenticated', 'Recipient exists as a contact'],
    mainFlow: [
      'User navigates to new transaction',
      'User selects recipient',
      'User enters amount and description',
      'User selects "Request" option',
      'User submits request',
      'System records transaction request with status PENDING_ACCEPTANCE',
      'Recipient is notified of payment request',
    ],
    postconditions: [
      'Payment request created (PENDING_ACCEPTANCE)',
      'Recipient can accept or reject',
      'Notification sent to recipient',
      'Request visible in both users\' transaction histories',
    ],
  },
  'UC-TRANSACTION-03': {
    // User views transaction list → Personal
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User has transactions'],
    mainFlow: [
      'User opens app or navigates to transactions',
      'Personal tab is selected (default)',
      'System fetches user\'s transactions from database',
      'Transactions displayed in chronological order',
    ],
    postconditions: ['Transaction list rendered with details (amount, date, recipient/sender)'],
  },
  'UC-TRANSACTION-04': {
    // User views transaction list → Public
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'Other users have public transactions'],
    mainFlow: [
      'User navigates to transaction feed',
      'User clicks "Public" tab',
      'System fetches public transactions from all users',
      'Transactions displayed with payer & recipient info (privacy rules applied)',
    ],
    postconditions: ['Public transactions displayed without sensitive data'],
  },
  'UC-TRANSACTION-05': {
    // User views transaction list → Contacts
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User has contacts', 'Contacts have transactions'],
    mainFlow: [
      'User clicks "Friends" tab',
      'System fetches transactions from user\'s contacts only',
      'Transactions displayed in list',
    ],
    postconditions: ['Contact-only transactions displayed'],
  },
  'UC-TRANSACTION-06': {
    // Accept/Reject payment request
    actors: ['Recipient (of payment request)'],
    preconditions: ['User has pending payment request', 'User is authenticated'],
    mainFlow: [
      'User sees pending payment request notification',
      'User navigates to transaction detail',
      'User clicks Accept or Reject',
      'If Accept: system transfers funds, updates balances',
      'If Reject: system marks request as REJECTED, no funds transfer',
      'Requester notified of decision',
    ],
    postconditions: [
      'Request status updated (ACCEPTED or REJECTED)',
      'Balances adjusted if accepted',
      'Both users notified',
    ],
  },

  // User module
  'UC-USER-01': {
    // User login
    actors: ['Unauthed User'],
    preconditions: ['User has account', 'Credentials are correct'],
    mainFlow: [
      'User navigates to login page',
      'User enters username',
      'User enters password',
      'User clicks login',
      'System validates credentials against database',
      'System creates session / issues auth token',
      'User redirected to home page',
    ],
    postconditions: ['User authenticated (session active)', 'User can access protected pages'],
  },
  'UC-USER-02': {
    // User views/edits profile
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated'],
    mainFlow: [
      'User navigates to user settings',
      'User views profile (first name, last name, email, phone, avatar)',
      'User can edit fields and save',
      'System updates user record in database',
    ],
    postconditions: ['User profile updated in database', 'Changes visible in app'],
  },
  'UC-USER-03': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated'],
    mainFlow: [
      'User navigates to user settings',
      'User views current balance',
    ],
    postconditions: ['Balance displayed accurately (reflects all transactions)'],
  },

  // Notification module
  'UC-NOTIFICATION-01': {
    // User receives notification
    actors: ['System', 'Recipient User'],
    preconditions: ['Event triggered (transaction sent/received, request sent)'],
    mainFlow: [
      'Event occurs (payment sent, request created, etc)',
      'System creates notification record',
      'System stores notification in database with unread status',
      'Recipient next logs in or refreshes',
      'Notification appears in notification center',
    ],
    postconditions: ['Notification stored and delivered', 'User can dismiss or view'],
  },

  // BankAccount module
  'UC-BANKACCOUNT-01': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User has bank accounts'],
    mainFlow: [
      'User navigates to bank accounts section',
      'System retrieves user\'s bank accounts from database',
      'Accounts displayed with account number, balance, type',
    ],
    postconditions: ['Bank accounts list rendered'],
  },
  'UC-BANKACCOUNT-02': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated'],
    mainFlow: [
      'User navigates to bank accounts',
      'User clicks "Add Bank Account"',
      'User enters account details (bank name, account number)',
      'User submits form',
      'System validates and stores account',
    ],
    postconditions: ['Bank account created', 'Account available for transactions'],
  },
  'UC-BANKACCOUNT-03': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User has bank account to delete'],
    mainFlow: [
      'User navigates to bank accounts',
      'User clicks delete on a bank account',
      'User confirms deletion',
      'System removes account from database',
    ],
    postconditions: ['Bank account deleted', 'No longer available for transfers'],
  },
  'UC-BANKACCOUNT-04': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User has bank account'],
    mainFlow: [
      'User navigates to bank account list',
      'User clicks on a bank account',
      'System displays account details & balance',
    ],
    postconditions: ['Account detail page displayed'],
  },

  // Like module
  'UC-LIKE-01': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'Transaction exists', 'User hasn\'t liked it'],
    mainFlow: [
      'User views transaction',
      'User clicks like/heart button',
      'System records like in database',
      'Like count incremented',
      'Button state changes to unliked',
    ],
    postconditions: ['Like recorded', 'Transaction owner notified', 'Like visible to other users'],
  },
  'UC-LIKE-02': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User has liked transaction'],
    mainFlow: [
      'User views transaction',
      'User clicks unlike button',
      'System removes like from database',
      'Like count decremented',
    ],
    postconditions: ['Like removed'],
  },

  // Comment module
  'UC-COMMENT-01': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'Transaction exists'],
    mainFlow: [
      'User views transaction detail',
      'User clicks comment input',
      'User types comment',
      'User submits',
      'System stores comment with timestamp and author',
    ],
    postconditions: ['Comment recorded', 'Comment visible to other users', 'Transaction owner notified'],
  },
  'UC-COMMENT-02': {
    actors: ['Authenticated User'],
    preconditions: ['User is authenticated', 'User is comment author'],
    mainFlow: [
      'User views comment on transaction',
      'User clicks delete',
      'System removes comment from database',
    ],
    postconditions: ['Comment deleted', 'No longer visible to other users'],
  },
};

let enrichedCount = 0;

// Apply enrichment rules to all BRD files
const brdFiles = fs.readdirSync(brdDir).filter(f => f.endsWith('.brd.json'));

for (const brdFile of brdFiles) {
  const brdPath = path.join(brdDir, brdFile);
  try {
    const brd = JSON.parse(fs.readFileSync(brdPath, 'utf8'));

    if (brd.useCases && brd.useCases.length) {
      for (const uc of brd.useCases) {
        if (enrichmentRules[uc.id]) {
          const rule = enrichmentRules[uc.id];
          Object.assign(uc, {
            actors: rule.actors || uc.actors,
            preconditions: rule.preconditions || uc.preconditions,
            mainFlow: rule.mainFlow || uc.mainFlow,
            postconditions: rule.postconditions || uc.postconditions,
            reviewStatus: 'enriched', // Mark as enriched
          });
          enrichedCount++;
        } else if (uc.status === 'code-inferred' && uc.reviewStatus === 'pending') {
          // Mark backend UCs that haven't been enriched as pending-review
          uc.reviewStatus = 'pending-enrichment';
        }
      }

      fs.writeFileSync(brdPath, JSON.stringify(brd, null, 2), 'utf8');
    }
  } catch (e) {
    console.error(`Error enriching ${brdFile}: ${e.message}`);
  }
}

console.log(`✓ Enriched ${enrichedCount} use cases with domain knowledge.`);
