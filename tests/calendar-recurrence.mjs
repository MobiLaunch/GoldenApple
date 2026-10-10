#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve, dirname } from "node:path";
import vm from "node:vm";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const code = readFileSync(resolve(root, "apps/calendar/recurrence.js"), "utf8")
    .replace(/^\s*\.pragma library\s*$/m, "");
const cal = vm.runInNewContext(code + "\n({ occursOn, occurrencesOn, summary, shiftDay, weekDays, displayedDays })");
const e = (date, repeat = "never", until = "") => ({id:"test", title:"Test", date, repeat, until});
const has = (event,date) => cal.occursOn(event,date);
assert.equal(has(e("2026-10-08"),"2026-10-08"),true);
assert.equal(has(e("2026-10-08"),"2026-10-09"),false);
assert.equal(has(e("2026-10-08","daily"),"2026-12-31"),true);
assert.equal(has(e("2026-10-08","daily","2026-10-10"),"2026-10-10"),true);
assert.equal(has(e("2026-10-08","daily","2026-10-10"),"2026-10-11"),false);
assert.equal(has(e("2026-10-08","weekly"),"2026-10-15"),true);
assert.equal(has(e("2026-10-08","weekly"),"2026-10-16"),false);
assert.equal(has(e("2026-10-08","weekly"),"2026-10-01"),false);
assert.equal(has(e("2026-10-29","weekly"),"2026-11-05"),true);
assert.equal(has(e("2026-01-31","monthly"),"2026-02-28"),false);
assert.equal(has(e("2026-01-31","monthly"),"2026-03-31"),true);
assert.equal(has(e("2028-02-29","yearly"),"2029-02-28"),false);
assert.equal(has(e("2028-02-29","yearly"),"2032-02-29"),true);
assert.equal(has(e("2026-10-08","yearly"),"2027-10-08"),true);
const source=e("2026-10-08","weekly");
const projected=cal.occurrencesOn([source,e("2026-10-09")],"2026-10-15");
assert.equal(projected.length,1);
assert.equal(projected[0].date,"2026-10-08");
assert.equal(projected[0].occurrenceDate,"2026-10-15");
assert.equal(source.occurrenceDate,undefined);
assert.equal(cal.summary(e("2026-10-08","weekly","2026-11-30")),"Weekly until 2026-11-30");
const recurring=e("2026-10-08","weekly");
recurring.exceptions={
    "2026-10-15":null,
    "2026-10-22":{title:"Moved",date:"2026-10-23",time:"15:00",calendar:"Home"}
};
assert.equal(cal.occurrencesOn([recurring],"2026-10-15").length,0);
assert.equal(cal.occurrencesOn([recurring],"2026-10-22").length,0);
const moved=cal.occurrencesOn([recurring],"2026-10-23");
assert.equal(moved.length,1);
assert.equal(moved[0].title,"Moved");
assert.equal(moved[0].date,"2026-10-08");
assert.equal(moved[0].occurrenceDate,"2026-10-22");
assert.equal(moved[0].displayedDate,"2026-10-23");
assert.equal(cal.occurrencesOn([recurring],"2026-10-29").length,1);
assert.equal(cal.shiftDay("2026-10-31",1),"2026-11-01");
assert.equal(cal.shiftDay("2028-02-28",1),"2028-02-29");
assert.equal(cal.shiftDay("2026-11-01",-1),"2026-10-31");
assert.equal(cal.weekDays("2026-10-08").join(","),[
    "2026-10-04","2026-10-05","2026-10-06","2026-10-07",
    "2026-10-08","2026-10-09","2026-10-10"].join(","));
assert.equal(cal.weekDays("2026-11-01")[0],"2026-11-01");
assert.equal(cal.displayedDays("day","2026-10-08").length,1);
assert.equal(cal.displayedDays("week","2026-10-08").length,7);
const agenda=cal.occurrencesOn([
    {...e("2026-10-08"),id:"b",title:"Afternoon",time:"15:00"},
    {...e("2026-10-08"),id:"a",title:"All-day",time:""},
    {...e("2026-10-08"),id:"c",title:"Morning",time:"09:00"}
],"2026-10-08");
assert.deepEqual(Array.from(agenda,x=>x.title),["All-day","Morning","Afternoon"]);
console.log("Calendar recurrence contracts passed");
