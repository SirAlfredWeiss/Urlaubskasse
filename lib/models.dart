class Trip {
  final String id;
  final String name;
  Trip({required this.id, required this.name});

  factory Trip.fromMap(Map<String, dynamic> m) => Trip(
        id: m['id'] as String,
        name: (m['name'] ?? 'Reise') as String,
      );
}

class Person {
  final String id;
  final String name;
  final String? color;
  final String? groupLabel;
  Person({required this.id, required this.name, this.color, this.groupLabel});

  factory Person.fromMap(Map<String, dynamic> m) => Person(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        color: m['color'] as String?,
        groupLabel: m['group_label'] as String?,
      );
}

class Participant {
  final String personId;
  final double? share;
  Participant({required this.personId, this.share});

  factory Participant.fromMap(Map<String, dynamic> m) => Participant(
        personId: m['person_id'] as String,
        share: (m['share'] as num?)?.toDouble(),
      );
}

class Expense {
  final String id;
  final String tripId;
  final String spentBy;
  final double amount;
  final String description;
  final String? expenseDate;
  final String? splitMethod;
  final List<Participant> participants;

  Expense({
    required this.id,
    required this.tripId,
    required this.spentBy,
    required this.amount,
    required this.description,
    this.expenseDate,
    this.splitMethod,
    required this.participants,
  });

  factory Expense.fromMap(
    Map<String, dynamic> m, {
    List<Participant> participants = const [],
  }) =>
      Expense(
        id: m['id'] as String,
        tripId: m['trip_id'] as String,
        spentBy: m['spent_by'] as String,
        amount: (m['amount'] as num).toDouble(),
        description: (m['description'] ?? '') as String,
        expenseDate: m['expense_date'] as String?,
        splitMethod: m['split_method'] as String?,
        participants: participants,
      );
}

class BudgetPeriod {
  final String id;
  final String tripId;
  final String startDate; // YYYY-MM-DD
  final String endDate;
  final double dailyAmount;
  final String? groupLabel; // welche Kasse

  BudgetPeriod({
    required this.id,
    required this.tripId,
    required this.startDate,
    required this.endDate,
    required this.dailyAmount,
    this.groupLabel,
  });

  factory BudgetPeriod.fromMap(Map<String, dynamic> m) => BudgetPeriod(
        id: m['id'] as String,
        tripId: m['trip_id'] as String,
        startDate: m['start_date'] as String,
        endDate: m['end_date'] as String,
        dailyAmount: (m['daily_amount'] as num).toDouble(),
        groupLabel: m['group_label'] as String?,
      );
}
