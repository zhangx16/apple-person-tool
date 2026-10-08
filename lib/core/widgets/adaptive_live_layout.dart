/// Grid sizing uses the available content width, including iPad split windows.
int liveRoomGridColumns(double width, {double textScale = 1}) {
  final scale = textScale.clamp(1.0, 2.0);
  final minimumCardWidth = 160 + (scale - 1) * 160;
  return ((width - 32 + 12) / (minimumCardWidth + 12)).floor().clamp(1, 6);
}
