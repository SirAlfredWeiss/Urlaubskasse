import 'models.dart';

// ---------------------------------------------------------------------------
// Datum-Helfer (ISO 'YYYY-MM-DD' laesst sich als String chronologisch sortieren)
// ---------------------------------------------------------------------------
String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> datesInRange(String start, String end) {
  DateTime s, e;
  try {
    s = DateTime.parse(start);
    e = DateTime.parse(end);
  } catch (_) {
    return [start];
  }
  if (e.isBefore(s)) return [start];
  final out = <String>[];
  var d = DateTime(s.year, s.month, s.day);
  final last = DateTime(e.year, e.month, e.day);
  var guard = 0;
  while (!d.isAfter(last) && guard < 1000) {
    out.add(fmtDate(d));
    d = d.add(const Duration(days: 1));
    guard++;
  }
  return out;
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String weekdayLabel(String date) {
  try {
    return _weekdays[DateTime.parse(date).weekday - 1];
  } catch (_) {
    return '';
  }
}

String dateLabel(String? d) {
  if (d == null || d.isEmpty) return '';
  final parts = d.split('-');
  if (parts.length == 3) return '${parts[2]}.${parts[1]}.';
  return d;
}

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------
double dailyBudgetForDate(List<BudgetPeriod> periods, String date) {
  var sum = 0.0;
  for (final p in periods) {
    if (p.startDate.compareTo(date) <= 0 && date.compareTo(p.endDate) <= 0) {
      sum += p.dailyAmount;
    }
  }
  return sum;
}

double totalBudget(List<BudgetPeriod> periods) {
  var sum = 0.0;
  for (final p in periods) {
    sum += p.dailyAmount * datesInRange(p.startDate, p.endDate).length;
  }
  return sum;
}

double totalSpent(List<Expense> expenses) =>
    expenses.fold(0.0, (a, e) => a + e.amount);

Map<String, double> spentByDay(List<Expense> expenses) {
  final m = <String, double>{};
  for (final e in expenses) {
    final d = e.expenseDate ?? '';
    m[d] = (m[d] ?? 0) + e.amount;
  }
  return m;
}

/// Alle relevanten Tage: aus Budget-Zeitraeumen + Tagen mit Ausgaben, sortiert.
List<String> tripDays(List<BudgetPeriod> periods, List<Expense> expenses) {
  final set = <String>{};
  for (final p in periods) {
    set.addAll(datesInRange(p.startDate, p.endDate));
  }
  for (final e in expenses) {
    if (e.expenseDate != null && e.expenseDate!.isNotEmpty) {
      set.add(e.expenseDate!);
    }
  }
  final list = set.toList()..sort();
  return list;
}

// ---------------------------------------------------------------------------
// Aufteilung einer Ausgabe auf die Beteiligten
// ---------------------------------------------------------------------------
Map<String, double> portionsFor(Expense e) {
  final parts = e.participants;
  if (parts.isEmpty) return {};

  final method = (e.splitMethod ?? '').toLowerCase();
  final exact = method.contains('exact') ||
      method.contains('amount') ||
      method.contains('betrag');

  final out = <String, double>{};
  if (exact) {
    for (final p in parts) {
      out[p.personId] = p.share ?? 0;
    }
    return out;
  }

  final anyNull = parts.any((p) => p.share == null);
  final weights = parts.map((p) => anyNull ? 1.0 : (p.share ?? 0)).toList();
  final sum = weights.fold<double>(0, (a, b) => a + b);
  final denom = sum == 0 ? parts.length.toDouble() : sum;
  for (var i = 0; i < parts.length; i++) {
    out[parts[i].personId] = e.amount * (weights[i] / denom);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Salden pro Person
// ---------------------------------------------------------------------------
class Balance {
  final Person person;
  final double net; // + = bekommt zurueck, - = schuldet
  Balance(this.person, this.net);
}

/// Buchungen werden gleichmaessig auf die Beteiligten geteilt.
Map<String, double> bookingPortions(Booking b) {
  final ids = b.participantIds;
  if (ids.isEmpty) return {};
  final each = b.amount / ids.length;
  return {for (final id in ids) id: each};
}

List<Balance> computeBalances(
  List<Person> persons,
  List<Expense> expenses, {
  List<Booking> bookings = const [],
}) {
  final paid = <String, double>{for (final p in persons) p.id: 0};
  final owes = <String, double>{for (final p in persons) p.id: 0};

  for (final e in expenses) {
    paid[e.spentBy] = (paid[e.spentBy] ?? 0) + e.amount;
    portionsFor(e).forEach((pid, amt) {
      owes[pid] = (owes[pid] ?? 0) + amt;
    });
  }
  for (final b in bookings) {
    paid[b.bookedBy] = (paid[b.bookedBy] ?? 0) + b.amount;
    bookingPortions(b).forEach((pid, amt) {
      owes[pid] = (owes[pid] ?? 0) + amt;
    });
  }

  return persons
      .map((p) => Balance(p, (paid[p.id] ?? 0) - (owes[p.id] ?? 0)))
      .toList();
}

// ---------------------------------------------------------------------------
// Gruppierung zu "Kassen" (per group_label). Personen ohne Label = eigene Kasse.
// ---------------------------------------------------------------------------
String kasseKey(Person p) {
  final g = p.groupLabel;
  if (g != null && g.trim().isNotEmpty) return 'g:${g.trim()}';
  return 'p:${p.id}';
}

class KasseBalance {
  final String key;
  final String label;
  final List<Person> members;
  final double net;
  KasseBalance(this.key, this.label, this.members, this.net);
}

List<KasseBalance> computeKassen(
  List<Person> persons,
  List<Expense> expenses, {
  List<Booking> bookings = const [],
}) {
  final balances = computeBalances(persons, expenses, bookings: bookings);
  final labels = <String, String>{};
  final members = <String, List<Person>>{};
  final nets = <String, double>{};

  for (final b in balances) {
    final key = kasseKey(b.person);
    final g = b.person.groupLabel;
    labels[key] = (g != null && g.trim().isNotEmpty) ? g.trim() : b.person.name;
    members.putIfAbsent(key, () => []).add(b.person);
    nets[key] = (nets[key] ?? 0) + b.net;
  }

  final list = nets.keys
      .map((k) => KasseBalance(k, labels[k]!, members[k]!, nets[k]!))
      .toList();
  list.sort((a, b) => b.net.compareTo(a.net));
  return list;
}

class KasseTransfer {
  final KasseBalance from;
  final KasseBalance to;
  final double amount;
  KasseTransfer(this.from, this.to, this.amount);
}

List<KasseTransfer> computeKasseSettlement(
  List<Person> persons,
  List<Expense> expenses, {
  List<Booking> bookings = const [],
}) {
  final kassen = computeKassen(persons, expenses, bookings: bookings);
  final byKey = {for (final k in kassen) k.key: k};

  final debtors = <MapEntry<String, double>>[];
  final creditors = <MapEntry<String, double>>[];
  for (final k in kassen) {
    final net = (k.net * 100).round() / 100;
    if (net < -0.005) debtors.add(MapEntry(k.key, -net));
    if (net > 0.005) creditors.add(MapEntry(k.key, net));
  }
  debtors.sort((a, b) => b.value.compareTo(a.value));
  creditors.sort((a, b) => b.value.compareTo(a.value));

  final dRem = debtors.map((e) => e.value).toList();
  final cRem = creditors.map((e) => e.value).toList();
  final transfers = <KasseTransfer>[];
  var i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final amt = dRem[i] < cRem[j] ? dRem[i] : cRem[j];
    transfers.add(
      KasseTransfer(byKey[debtors[i].key]!, byKey[creditors[j].key]!, amt),
    );
    dRem[i] -= amt;
    cRem[j] -= amt;
    if (dRem[i] < 0.005) i++;
    if (cRem[j] < 0.005) j++;
  }
  return transfers;
}

// ---------------------------------------------------------------------------
String euro(double v) {
  final s = v.abs().toStringAsFixed(2).replaceAll('.', ',');
  return '${v < 0 ? '-' : ''}$s €';
}

// ---------------------------------------------------------------------------
// Kassen-Sicht: "wer bin ich" -> meine Kasse und mein Anteil
// ---------------------------------------------------------------------------
String kasseLabelOf(Person p) {
  final g = p.groupLabel;
  return (g != null && g.trim().isNotEmpty) ? g.trim() : p.name;
}

Set<String> kasseMemberIds(Person me, List<Person> all) {
  final key = kasseKey(me);
  return all.where((p) => kasseKey(p) == key).map((p) => p.id).toSet();
}

/// Anteil MEINER Kasse an einer Ausgabe (Summe der Anteile meiner Mitglieder).
double kasseShareOfExpense(Expense e, Set<String> memberIds) {
  final portions = portionsFor(e);
  var s = 0.0;
  for (final id in memberIds) {
    s += portions[id] ?? 0;
  }
  return s;
}

double kasseShareOfBooking(Booking b, Set<String> memberIds) {
  final ids = b.participantIds;
  if (ids.isEmpty) return 0;
  final n = ids.where(memberIds.contains).length;
  return n * (b.amount / ids.length);
}
