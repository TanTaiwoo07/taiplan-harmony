#!/usr/bin/env node
'use strict';
// Node 24 standard library only. Reads an exported desktop SQLite backup;
// never opens the source DB in SQLite and never reads config or credentials.
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { createHash } = require('node:crypto');

function day(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) throw Error('日期格式无效');
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(y, m - 1, d, 12);
  if (y < 2000 || y > 2100 || date.getFullYear() !== y || date.getMonth() !== m - 1 || date.getDate() !== d) throw Error('日期不存在或超出 2000～2100');
  return date;
}
function end(value) { const date = day(value); date.setHours(23, 59, 59, 999); return date.getTime(); }
function minute(value) {
  if (!value) return -1;
  if (!/^\d{2}:\d{2}$/.test(value)) throw Error('时间不是 HH:MM');
  const [h, m] = value.split(':').map(Number);
  if (h > 23 || m > 59) throw Error('时间无效');
  return h * 60 + m;
}
function timestamp(value, fallback) {
  if (!value) return fallback;
  const stamp = new Date(value.replace(' ', 'T')).getTime();
  if (!Number.isSafeInteger(stamp) || stamp < 0) throw Error('创建或更新时间无效');
  return stamp;
}
function occurs(task, key) {
  const target = day(key), anchor = new Date(task.dueAt);
  const targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
  const anchorDay = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate()).getTime();
  if (targetDay < anchorDay) return false;
  if (task.repeat === 'daily') return true;
  if (task.repeat === 'weekly') return target.getDay() === anchor.getDay();
  const last = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
  return target.getDate() === Math.min(anchor.getDate(), last);
}
function convertTask(row, namespace, now) {
  if (!Number.isSafeInteger(row.id) || row.id < 1) throw Error('任务 ID 无效');
  if (typeof row.title !== 'string' || !row.title.trim() || row.title.trim().length > 100) throw Error('标题长度超出 1～100 字');
  if (![0, 1].includes(row.is_completed)) throw Error('完成状态无效');
  const note = [row.description || '', row.url ? `链接：${row.url}` : ''].filter(Boolean).join('\n');
  if (note.length > 1000) throw Error('备注与链接合并后超过 1000 字，未截断原文');
  const priority = { low: 0, normal: 1, urgent: 2 }[row.priority];
  if (priority === undefined) throw Error('优先级无效');
  let repeat = 'none';
  if (row.is_recurring) {
    if (!['daily', 'weekly', 'monthly'].includes(row.recurrence_frequency) || (row.recurrence_interval ?? 1) !== 1 ||
      !['never', '', null, undefined].includes(row.recurrence_end_type) || row.recurrence_end_date || row.recurrence_stop_before) {
      throw Error('暂不支持此重复频率、间隔、结束日或停止规则；整个系列保留在原备份中');
    }
    repeat = row.recurrence_frequency;
  }
  const dueAt = row.date ? end(row.date) : 0;
  const startMinute = minute(row.time);
  const durationMinutes = startMinute >= 0 ? (row.duration_minutes ?? 30) : 30;
  if ((repeat !== 'none' || startMinute >= 0) && dueAt === 0) throw Error('重复或定时任务缺少日期');
  if (!Number.isInteger(durationMinutes) || durationMinutes < 5 || durationMinutes > 1440 ||
    (startMinute >= 0 && startMinute + durationMinutes > 1440)) throw Error('时长小于 5 分钟或跨日，未缩短原事件');
  const createdAt = timestamp(row.created_at, now);
  return { id: `desktop:${namespace}:${row.id}`, title: row.title.trim(), note, completed: repeat === 'none' && row.is_completed === 1,
    createdAt, updatedAt: timestamp(row.updated_at, createdAt), priority, tags: ['桌面导入'], dueAt, repeat, sortOrder: -createdAt,
    startMinute, durationMinutes, steps: [], doneSteps: [] };
}
function occurrenceKey(key, row, task) {
  if (typeof key !== 'string' || !/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$/.test(key)) throw Error('单次记录的键格式无效');
  const [date, time] = key.split('T');
  if ((time || '') !== (row.time || '') || !occurs(task, date)) throw Error('单次记录与当前重复规则不一致');
  return date;
}
function convertRows(rows, states, overrides, namespace, now = Date.now()) {
  if (!/^[a-zA-Z0-9_-]{1,32}$/.test(namespace || '')) throw Error('namespace 必须为 1～32 位英文、数字、下划线或短横线；同一数据库请始终使用同一个值');
  const tasks = [], occurrences = [], notes = [];
  let skipped = 0;
  for (const row of rows) {
    try {
      const task = convertTask(row, namespace, now);
      const dates = new Map(), moved = [];
      if (task.repeat !== 'none') {
        for (const record of states.filter(s => s.task_id === row.id)) {
          const dateKey = occurrenceKey(record.occurrence_key, row, task);
          if (!['completed', 'cancelled', 'pending'].includes(record.status)) throw Error('单次记录状态不支持');
          dates.set(dateKey, { taskId: task.id, dateKey, completed: record.status === 'completed', skipped: record.status === 'cancelled',
            updatedAt: timestamp(record.updated_at, now), doneSteps: [] });
        }
        // Older desktop releases could mark a recurring master completed.
        if (row.is_completed && !dates.has(row.date)) dates.set(row.date, { taskId: task.id, dateKey: row.date, completed: true, skipped: false, updatedAt: now, doneSteps: [] });
        for (const override of overrides.filter(o => o.task_id === row.id)) {
          const key = occurrenceKey(override.occurrence_key, row, task);
          const previous = dates.get(key);
          if (!previous?.skipped) {
            const movedRow = { ...row, is_recurring: 0, date: override.override_date ?? key,
              time: override.override_time ?? row.time, duration_minutes: override.override_duration_minutes ?? row.duration_minutes,
              is_completed: previous?.completed ? 1 : 0 };
            const single = convertTask(movedRow, namespace, now);
            single.id = `${task.id}:moved:${key}`;
            moved.push(single);
          }
          dates.set(key, { taskId: task.id, dateKey: key, completed: false, skipped: true, updatedAt: now, doneSteps: [] });
        }
      } else if (states.some(s => s.task_id === row.id) || overrides.some(o => o.task_id === row.id)) {
        throw Error('普通任务仍有关联的重复记录，需先在桌面版检查');
      }
      tasks.push(task, ...moved); occurrences.push(...dates.values());
      if (moved.length) notes.push(`任务 ${row.id}：${moved.length} 条单次改期转换为独立任务，原日期标记跳过。`);
      if (task.startMinute >= 0 && row.duration_minutes == null) notes.push(`任务 ${row.id}：原任务未设置时长，采用 30 分钟。`);
    } catch (error) { skipped++; notes.push(`任务 ${row.id} 未转换：${error.message}`); }
  }
  if (tasks.length > 5000 || occurrences.length > 50000) throw Error('数据超过鸿蒙备份数量上限');
  const document = { format: 'TaiPlanHarmony', version: 4, exportedAt: now, tasks, occurrences };
  const raw = JSON.stringify(document, null, 2);
  if (Buffer.byteLength(raw) > 4 * 1024 * 1024) throw Error('转换结果超过 4 MB，未输出不完整备份');
  return { document, report: { sourceTasks: rows.length, convertedSourceTasks: rows.length - skipped,
    outputTasks: tasks.length, occurrenceRecords: occurrences.length, skippedSourceTasks: skipped, namespace, notes } };
}

function transfer(input, output, namespace) {
  input = path.resolve(input); output = path.resolve(output);
  const reportPath = output + '.report.json';
  if (input === output || fs.existsSync(output) || fs.existsSync(reportPath)) throw Error('输出文件已存在，请换一个新文件名；不会覆盖现有文件');
  if (fs.existsSync(input + '-wal')) throw Error('检测到 WAL 文件。请先在桌面版导出一致性数据库备份，再转换备份文件');
  if (!fs.statSync(input).isFile()) throw Error('输入不是普通文件');
  const directory = path.dirname(output);
  fs.mkdirSync(directory, { recursive: true });
  const temporary = fs.mkdtempSync(path.join(directory, '.taiplan-transfer-'));
  const snapshot = path.join(temporary, 'source.db');
  let db;
  try {
    const before = fs.statSync(input);
    fs.copyFileSync(input, snapshot, fs.constants.COPYFILE_EXCL);
    const after = fs.statSync(input);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs) throw Error('源文件复制期间发生变化，请改用桌面版导出的静态备份');
    db = new DatabaseSync(snapshot, { readOnly: true });
    if (db.prepare('PRAGMA quick_check').get().quick_check !== 'ok') throw Error('数据库完整性检查失败');
    const tables = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r => r.name));
    if (!tables.has('tasks')) throw Error('不是 TaiPlan 桌面任务数据库');
    const rows = db.prepare('SELECT * FROM tasks ORDER BY id').all();
    const states = tables.has('task_occurrence_states') ? db.prepare('SELECT * FROM task_occurrence_states').all() : [];
    const overrides = tables.has('task_occurrence_overrides') ? db.prepare('SELECT * FROM task_occurrence_overrides').all() : [];
    const result = convertRows(rows, states, overrides, namespace);
    result.report.sourceSha256 = createHash('sha256').update(fs.readFileSync(snapshot)).digest('hex');
    fs.writeFileSync(output, JSON.stringify(result.document, null, 2), { encoding: 'utf8', flag: 'wx' });
    fs.writeFileSync(reportPath, JSON.stringify(result.report, null, 2), { encoding: 'utf8', flag: 'wx' });
    return result.report;
  } finally {
    db?.close();
    const resolved = fs.realpathSync(temporary);
    if (path.dirname(resolved) === fs.realpathSync(directory) && path.basename(resolved).startsWith('.taiplan-transfer-')) {
      fs.rmSync(resolved, { recursive: true });
    }
  }
}
module.exports = { convertRows, transfer };
if (require.main === module) {
  const [input, output, namespace] = process.argv.slice(2);
  if (!input || !output || !namespace) {
    console.error('用法：node tools/desktop-transfer.cjs 桌面备份.db 新备份.json 数据源名称'); process.exitCode = 1;
  } else {
    try { console.log(JSON.stringify(transfer(input, output, namespace), null, 2)); }
    catch (error) { console.error(error.message); process.exitCode = 1; }
  }
}
