test(dynamic x) {
  const y = 1;
  switch (x) {
    case y as Object:
      break;
  }
}
