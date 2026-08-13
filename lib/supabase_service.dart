import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

class UrlaubskasseService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<Trip>> fetchTrips() async {
    final rows = await _db
        .from('urlaub_trips')
        .select('id, name, created_at')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>().map(Trip.fromMap).toList();
  }

  Future<List<Person>> fetchPersons(String tripId) async {
    final rows = await _db
        .from('urlaub_persons')
        .select('id, name, color, group_label')
        .eq('trip_id', tripId)
        .order('name');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Person.fromMap)
        .toList();
  }

  // Laedt ALLE Ausgaben der Reise (ueber trip_id).
  Future<List<Expense>> fetchExpenses(String tripId) async {
    final expRows = await _db
        .from('urlaub_expenses')
        .select(
            'id, trip_id, spent_by, amount, description, expense_date, split_method, created_at')
        .eq('trip_id', tripId)
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false);

    final expenses = (expRows as List).cast<Map<String, dynamic>>();
    if (expenses.isEmpty) return [];

    final ids = expenses.map((e) => e['id'] as String).toList();
    final partRows = await _db
        .from('urlaub_expense_participants')
        .select('expense_id, person_id, share')
        .inFilter('expense_id', ids);

    final byExpense = <String, List<Participant>>{};
    for (final row in (partRows as List).cast<Map<String, dynamic>>()) {
      final eid = row['expense_id'] as String;
      byExpense.putIfAbsent(eid, () => []).add(Participant.fromMap(row));
    }

    return expenses
        .map((m) => Expense.fromMap(m, participants: byExpense[m['id']] ?? []))
        .toList();
  }

  Future<List<BudgetPeriod>> fetchBudgetPeriods(String tripId) async {
    final rows = await _db
        .from('urlaub_budget_periods')
        .select('id, trip_id, start_date, end_date, daily_amount')
        .eq('trip_id', tripId)
        .order('start_date');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(BudgetPeriod.fromMap)
        .toList();
  }

  Future<void> addExpense({
    required String tripId,
    required String spentBy,
    required double amount,
    required String description,
    required String expenseDate,
    required String splitMethod,
    required List<Map<String, dynamic>> participants,
  }) async {
    final inserted = await _db
        .from('urlaub_expenses')
        .insert({
          'trip_id': tripId,
          'spent_by': spentBy,
          'amount': amount,
          'description': description,
          'expense_date': expenseDate,
          'split_method': splitMethod,
        })
        .select('id')
        .single();

    await _insertParticipants(inserted['id'] as String, participants);
  }

  Future<void> updateExpense({
    required String id,
    required String spentBy,
    required double amount,
    required String description,
    required String expenseDate,
    required String splitMethod,
    required List<Map<String, dynamic>> participants,
  }) async {
    await _db.from('urlaub_expenses').update({
      'spent_by': spentBy,
      'amount': amount,
      'description': description,
      'expense_date': expenseDate,
      'split_method': splitMethod,
    }).eq('id', id);

    await _db.from('urlaub_expense_participants').delete().eq('expense_id', id);
    await _insertParticipants(id, participants);
  }

  Future<void> deleteExpense(String id) async {
    await _db.from('urlaub_expense_participants').delete().eq('expense_id', id);
    await _db.from('urlaub_expenses').delete().eq('id', id);
  }

  Future<void> _insertParticipants(
      String expenseId, List<Map<String, dynamic>> participants) async {
    final rows = participants
        .map((p) => {
              'expense_id': expenseId,
              'person_id': p['person_id'],
              'share': p['share'],
            })
        .toList();
    if (rows.isNotEmpty) {
      await _db.from('urlaub_expense_participants').insert(rows);
    }
  }

  Future<void> addBudgetPeriod({
    required String tripId,
    required String startDate,
    required String endDate,
    required double dailyAmount,
  }) async {
    await _db.from('urlaub_budget_periods').insert({
      'trip_id': tripId,
      'start_date': startDate,
      'end_date': endDate,
      'daily_amount': dailyAmount,
    });
  }

  Future<void> deleteBudgetPeriod(String id) async {
    await _db.from('urlaub_budget_periods').delete().eq('id', id);
  }
}
