enum CoffeeType {
  jenfel,
  yetatebe,
  special;

  String get displayName {
    switch (this) {
      case CoffeeType.jenfel:
        return 'Jenfel';
      case CoffeeType.yetatebe:
        return 'Yetatebe';
      case CoffeeType.special:
        return 'Special';
    }
  }

  String get id {
    return name;
  }
}
