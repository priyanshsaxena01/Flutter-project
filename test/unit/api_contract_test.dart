import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/core/device/file_picker_service.dart';
import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/features/alerts/data/alert_repository.dart';
import 'package:fraud_shield/features/auth/data/auth_repository.dart';
import 'package:fraud_shield/features/cases/data/case_repository.dart';
import 'package:fraud_shield/features/disputes/data/dispute_repository.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/instruments/data/instrument_repository.dart';
import 'package:fraud_shield/features/instruments/domain/instrument.dart';
import 'package:fraud_shield/features/security/data/security_repository.dart';

import '../helpers/test_app.dart';

/// The API contract of the problem statement, exercised through the real
/// Dio client, interceptors and repositories against the in-app server.
void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());

  group('deny (idempotent: one block, one case)', () {
    test(
      'deny twice with one key -> one block, one case, same answer',
      () async {
        final c = await h.container();
        final repo = c.read(alertRepositoryProvider);
        final casesBefore = h.server.db.cases.length;

        final first = await repo.deny('alt_1004', idempotencyKey: 'k-1');
        final second = await repo.deny('alt_1004', idempotencyKey: 'k-1');

        expect(second.caseId, first.caseId);
        expect(h.server.blockActions, 1);
        expect(h.server.db.cases.length, casesBefore + 1);
        expect(h.server.db.instruments['ins_credit']!['blocked'], isTrue);
      },
    );

    test(
      'deny tapped twice on a slow network (concurrent) -> one case',
      () async {
        final c = await h.container();
        final repo = c.read(alertRepositoryProvider);
        final casesBefore = h.server.db.cases.length;

        final results = await Future.wait([
          repo.deny('alt_1004', idempotencyKey: 'same'),
          repo.deny('alt_1004', idempotencyKey: 'same'),
        ]);

        expect(results[0].caseId, results[1].caseId);
        expect(h.server.blockActions, 1);
        expect(h.server.db.cases.length, casesBefore + 1);
      },
    );

    test('a retry with a new key after success is still "done"', () async {
      final c = await h.container();
      final repo = c.read(alertRepositoryProvider);
      final first = await repo.deny('alt_1004', idempotencyKey: 'a');
      final again = await repo.deny('alt_1004', idempotencyKey: 'b');
      expect(again.alreadyDone, isTrue);
      expect(again.caseId, first.caseId);
      expect(h.server.blockActions, 1);
    });

    test('confirm then deny -> 409 ALREADY_CONFIRMED', () async {
      final c = await h.container();
      final repo = c.read(alertRepositoryProvider);
      await repo.confirm('alt_1003');
      await expectLater(
        repo.deny('alt_1003', idempotencyKey: 'x'),
        throwsA(
          isA<ConflictError>().having(
            (e) => e.code,
            'code',
            'ALREADY_CONFIRMED',
          ),
        ),
      );
    });

    test('mutations without an Idempotency-Key are refused', () async {
      final c = await h.container();
      await expectLater(
        c.read(dioProvider).post<Object?>('/alerts/alt_1004/deny'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            400,
          ),
        ),
      );
    });
  });

  group('instruments', () {
    test('block is idempotent: already blocked counts as success', () async {
      final c = await h.container();
      final repo = c.read(instrumentRepositoryProvider);
      final result = await repo.block(
        'ins_debit', // blocked in the demo data
        BlockReason.stolen,
        idempotencyKey: 'k',
      );
      expect(result.blocked, isTrue);
      expect(h.server.blockActions, 0);
    });

    test('lost or stolen cannot be unblocked', () async {
      final c = await h.container();
      final repo = c.read(instrumentRepositoryProvider);
      await repo.block('ins_upi', BlockReason.lost, idempotencyKey: 'b1');
      await expectLater(
        repo.unblock('ins_upi', idempotencyKey: 'u1'),
        throwsA(isA<ConflictError>()),
      );
    });
  });

  group('disputes', () {
    test('422 by reason: missing answers are named per question', () async {
      final c = await h.container();
      await expectLater(
        c
            .read(disputeRepositoryProvider)
            .create(
              txnId: 'txn_3011',
              reason: DisputeReason.notReceived,
              answers: const {},
              idempotencyKey: 'd1',
            ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.fieldErrors.keys,
            'fields',
            containsAll(['itemDescription', 'expectedBy', 'contactedMerchant']),
          ),
        ),
      );
    });

    test('older than 90 days is refused with an explanation', () async {
      final c = await h.container();
      await expectLater(
        c
            .read(disputeRepositoryProvider)
            .create(
              txnId: 'txn_3012',
              reason: DisputeReason.unauthorised,
              answers: const {'instrumentWithYou': 'yes', 'sharedOtp': 'no'},
              idempotencyKey: 'd2',
            ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('1800-123-4567'),
          ),
        ),
      );
    });

    test('evidence is required to submit "not received"', () async {
      final c = await h.container();
      final repo = c.read(disputeRepositoryProvider);
      final draft = await repo.create(
        txnId: 'txn_3013',
        reason: DisputeReason.notReceived,
        answers: const {
          'itemDescription': 'Running shoes',
          'expectedBy': '2026-09-15',
          'contactedMerchant': 'no',
        },
        idempotencyKey: 'd3',
      );
      await expectLater(
        repo.submit(draft.id, idempotencyKey: 's1'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            'EVIDENCE_REQUIRED',
          ),
        ),
      );

      await repo.uploadEvidence(draft.id, smallPng(), idempotencyKey: 'e1');
      final opened = await repo.submit(draft.id, idempotencyKey: 's1');
      expect(opened.caseNumber, 'FS-2026-000500');
      expect(opened.evidence.single.name, 'receipt.png');
    });

    test('413 for a file over 5 MB; a 6th file is refused', () async {
      final c = await h.container();
      final repo = c.read(disputeRepositoryProvider);
      final draft = await repo.create(
        txnId: 'txn_3013',
        reason: DisputeReason.unauthorised,
        answers: const {'instrumentWithYou': 'yes', 'sharedOtp': 'no'},
        idempotencyKey: 'd4',
      );
      await expectLater(
        repo.uploadEvidence(
          draft.id,
          PickedFile(
            name: 'big.jpg',
            sizeBytes: 6 * 1024 * 1024,
            mimeType: 'image/jpeg',
          ),
          idempotencyKey: 'big',
        ),
        throwsA(isA<PayloadTooLargeError>()),
      );
      for (var i = 0; i < 5; i++) {
        await repo.uploadEvidence(
          draft.id,
          smallPng('f$i.png'),
          idempotencyKey: 'e$i',
        );
      }
      await expectLater(
        repo.uploadEvidence(draft.id, smallPng('f6.png'), idempotencyKey: 'e6'),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'a second dispute for the same payment -> 409 with the case id',
      () async {
        final c = await h.container();
        await expectLater(
          c
              .read(disputeRepositoryProvider)
              .create(
                txnId: 'txn_3007', // already has case_481
                reason: DisputeReason.unauthorised,
                answers: const {'instrumentWithYou': 'yes', 'sharedOtp': 'no'},
                idempotencyKey: 'd5',
              ),
          throwsA(
            isA<ConflictError>().having(
              (e) => e.details['caseId'],
              'caseId',
              'case_481',
            ),
          ),
        );
      },
    );
  });

  group('cases, messages, devices, audit', () {
    test('case 404 is a NotFoundError', () async {
      final c = await h.container();
      await expectLater(
        c.read(caseRepositoryProvider).fetch('nope'),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('messages paginate newest first; sending adds a reply', () async {
      final c = await h.container();
      final repo = c.read(caseRepositoryProvider);
      final page1 = await repo.messages('case_462');
      expect(page1.items, hasLength(15));
      expect(page1.nextCursor, '15');
      final page2 = await repo.messages('case_462', cursor: page1.nextCursor);
      expect(page2.items, hasLength(9));
      expect(page2.nextCursor, isNull);
      expect(page1.items.first.at.isAfter(page2.items.first.at), isTrue);

      await repo.send('case_462', 'Any update?', idempotencyKey: 'm1');
      await repo.send('case_462', 'Any update?', idempotencyKey: 'm1'); // retry
      final latest = await repo.messages('case_462');
      expect(latest.items.where((m) => m.text == 'Any update?'), hasLength(1));
    });

    test('messaging on a breached case escalates it', () async {
      final c = await h.container();
      final repo = c.read(caseRepositoryProvider);
      await repo.send('case_437', 'Still waiting', idempotencyKey: 'm2');
      final updated = await repo.fetch('case_437');
      expect(
        updated.timeline.map((t) => t.title),
        contains('Escalated to a senior disputes officer'),
      );
    });

    test('the current device cannot remove itself (409 CURRENT)', () async {
      final c = await h.container();
      final repo = c.read(securityRepositoryProvider);
      final devices = await repo.devices();
      expect(devices.first.current, isTrue);
      await expectLater(
        repo.signOutDevice(TestHarness.device.id),
        throwsA(isA<ConflictError>().having((e) => e.code, 'code', 'CURRENT')),
      );
      await repo.signOutDevice('dev_ipad');
      expect(
        (await repo.devices()).map((d) => d.id),
        isNot(contains('dev_ipad')),
      );
    });

    test('every action is logged with device id and client time', () async {
      final c = await h.container();
      await c.read(alertRepositoryProvider).confirm('alt_1003');
      final log = await c.read(securityRepositoryProvider).auditLog();
      expect(log.first.action, 'POST /alerts/alt_1003/confirm');
      expect(log.first.deviceId, TestHarness.device.id);
      expect(log.first.clientAt, isNotNull);
      expect(() => h.server.auditLog.add({}), throwsUnsupportedError);
    });
  });

  group('auth and errors', () {
    test('wrong PIN counts down, then locks', () async {
      final c = await h.container(signedIn: false);
      final auth = c.read(authRepositoryProvider);
      await expectLater(
        auth.login(customerId: 'TEST_CUSTOM', pin: '0000'),
        throwsA(
          isA<UnauthorizedError>().having(
            (e) => e.message,
            'message',
            contains('4 attempts left'),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await expectLater(
          auth.login(customerId: 'TEST_CUSTOM', pin: '0000'),
          throwsA(isA<UnauthorizedError>()),
        );
      }
      await expectLater(
        auth.login(customerId: 'TEST_CUSTOM', pin: '0000'),
        throwsA(isA<LockedError>()),
      );
    });

    test(
      'offline and server errors become plain-language BankErrors',
      () async {
        final c = await h.container();
        final repo = c.read(alertRepositoryProvider);
        h.server.chaos.failNextRequest = true;
        await expectLater(repo.fetchAlerts(), throwsA(isA<ServerError>()));
        h.server.setOffline(true);
        await expectLater(repo.fetchAlerts(), throwsA(isA<NetworkError>()));
        h.server.setOffline(false);
        expect(await repo.fetchAlerts(), isNotEmpty);
      },
    );
  });
}
