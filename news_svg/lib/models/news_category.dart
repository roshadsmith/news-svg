enum NewsCategory {
  local,
  regional,
  international,
}

extension NewsCategoryLabel on NewsCategory {
  String get label {
    switch (this) {
      case NewsCategory.local:
        return 'Local';
      case NewsCategory.regional:
        return 'Regional';
      case NewsCategory.international:
        return 'International';
    }
  }

  String get storageKey {
    return name;
  }
}

NewsCategory newsCategoryFromStorage(String? value) {
  switch (value) {
    case 'regional':
      return NewsCategory.regional;
    case 'international':
      return NewsCategory.international;
    case 'local':
    default:
      return NewsCategory.local;
  }
}
