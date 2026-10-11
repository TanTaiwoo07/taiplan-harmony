export class TimeZoneService {
  private static civil(timestamp: number, formatter: Intl.DateTimeFormat): number {
    const parts = formatter.formatToParts(new Date(timestamp));
    const number = (name: string): number => Number(parts.find(part => part.type === name)?.value ?? 0);
    return Date.UTC(number('year'), number('month') - 1, number('day'), number('hour') % 24, number('minute'), number('second'));
  }
  static timestamp(year: number, month: number, day: number, hour: number, minute: number, zone: string): number {
    let formatter: Intl.DateTimeFormat;
    try { formatter = new Intl.DateTimeFormat('en-GB', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }); }
    catch { throw new Error('设备时区库不支持 ' + zone); }
    const target = Date.UTC(year, month - 1, day, hour, minute);
    const offsets = new Set<number>();
    for (let sample = -36; sample <= 36; sample += 6) { const utc = target + sample * 3600000; offsets.add(TimeZoneService.civil(utc, formatter) - utc); }
    const candidates: number[] = [];
    for (const offset of offsets) { const utc = target - offset; if (TimeZoneService.civil(utc, formatter) === target) { candidates.push(utc); } }
    if (!candidates.length) { throw new Error('该时区的此时刻不存在（夏令时跳变）'); }
    // RFC 5545 uses the first occurrence when a wall-clock time appears twice.
    return Math.min(...candidates);
  }
}
