import 'models.dart';

/// Anteil, den jede beteiligte Person fuer EINE Ausgabe schuldet.
/// Deckt gleichmaessig / Gewichte / Anteile / feste Betraege ab.
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

class Balance {
  final Person person;
  final double net; // positiv = bekommt zurueck, negativ = schuldet
  Balance(this.person, this.net);
}

List<Balance> computeBalances(List<Person> persons, List<Expense> expenses) {
  final paid = <String, double>{for (final p in persons) p.id: 0};
  final owes = <String, double>{for (final p in persons) p.id: 0};

  for (final e in expenses) {
    paid[e.spentBy] = (paid[e.spentBy] ?? 0) + e.amount;
    portionsFor(e).forEach((pid, amt) {
      owes[pid] = (owes[pid] ?? 0) + amt;
    });
  }

  final list = persons
      .map((p) => Balance(p, (paid[p.id] ?? 0) - (owes[p.id] ?? 0)))
      .toList();
  list.sort((a, b) => b.net.compareTo(a.net));
  return list;
}

class Transfer {
  final Person from;
  final Person to;
  final double amount;
  Transfer(this.from, this.to, this.amount);
}

List<Transfer> computeSettlement(List<Person> persons, List<Expense> expenses) {
  final byId = {for (final p in persons) p.id: p};
  final balances = computeBalances(persons, expenses);

  final debtors = <MapEntry<String, double>>[];
  final creditors = <MapEntry<String, double>>[];
  for (final b in balances) {
    final net = (b.net * 100).round() / 100;
    if (net < -0.005) debtors.add(MapEntry(b.person.id, -net));
    if (net > 0.005) creditors.add(MapEntry(b.person.id, net));
  }
  debtors.sort((a, b) => b.value.compareTo(a.value));
  creditors.sort((a, b) => b.value.compareTo(a.value));

  final dRem = debtors.map((e) => e.value).toList();
  final cRem = creditors.map((e) => e.value).toList();
  final transfers = <Transfer>[];
  var i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final amt = dRem[i] < cRem[j] ? dRem[i] : cRem[j];
    transfers.add(
      Transfer(byId[debtors[i].key]!, byId[creditors[j].key]!, amt),
    );
    dRem[i] -= amt;
    cRem[j] -= amt;
    if (dRem[i] < 0.005) i++;
    if (cRem[j] < 0.005) j++;
  }
  return transfers;
}

String euro(double v) {
  final s = v.abs().toStringAsFixed(2).replaceAll('.', ',');
  return '${v < 0 ? '-' : ''}$s €';
}

String dateLabel(String? d) {
  if (d == null || d.isEmpty) return '';
  final parts = d.split('-');
  if (parts.length == 3) return '${parts[2]}.${parts[1]}.';
  return d;
}
