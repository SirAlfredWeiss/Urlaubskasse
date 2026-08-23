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
  final String? category;
  final List<Participant> participants;
  final List<ExpenseItem> items;

  Expense({
    required this.id,
    required this.tripId,
    required this.spentBy,
    required this.amount,
    required this.description,
    this.expenseDate,
    this.splitMethod,
    this.category,
    required this.participants,
    this.items = const [],
  });

  factory Expense.fromMap(
    Map<String, dynamic> m, {
    List<Participant> participants = const [],
    List<ExpenseItem> items = const [],
  }) =>
      Expense(
        id: m['id'] as String,
        tripId: m['trip_id'] as String,
        spentBy: m['spent_by'] as String,
        amount: (m['amount'] as num).toDouble(),
        description: (m['description'] ?? '') as String,
        expenseDate: m['expense_date'] as String?,
        splitMethod: m['split_method'] as String?,
        category: m['category'] as String?,
        participants: participants,
        items: items,
      );
}

class ExpenseItem {
  final String? id;
  final double amount;
  final List<String> personIds;
  ExpenseItem({this.id, required this.amount, required this.personIds});

  factory ExpenseItem.fromMap(Map<String, dynamic> m) => ExpenseItem(
        id: m['id'] as String?,
        amount: (m['amount'] as num).toDouble(),
        personIds:
            ((m['person_ids'] as List?) ?? const []).map((e) => e as String).toList(),
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

class Booking {
  final String id;
  final String tripId;
  final String bookedBy;
  final String title;
  final double amount;
  final String? bookingDate;
  final String? ticketNumber;
  final String? note;
  final List<String> participantIds;

  Booking({
    required this.id,
    required this.tripId,
    required this.bookedBy,
    required this.title,
    required this.amount,
    this.bookingDate,
    this.ticketNumber,
    this.note,
    this.participantIds = const [],
  });

  factory Booking.fromMap(
    Map<String, dynamic> m, {
    List<String> participantIds = const [],
  }) =>
      Booking(
        id: m['id'] as String,
        tripId: m['trip_id'] as String,
        bookedBy: m['booked_by'] as String,
        title: (m['title'] ?? 'Buchung') as String,
        amount: (m['amount'] as num).toDouble(),
        bookingDate: m['booking_date'] as String?,
        ticketNumber: m['ticket_number'] as String?,
        note: m['note'] as String?,
        participantIds: participantIds,
      );
}
