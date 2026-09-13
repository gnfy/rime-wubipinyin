-- tools/test_datetime.lua —— lua/datetime.lua 的单元测试
--
-- 用法（需要本机有 lua 5.x）：
--   lua tools/test_datetime.lua
--
-- 用一个最小的假 librime-lua 环境（Candidate / yield / seg / env）驱动模块，
-- 不依赖 Rime 本体。格式断言用固定时间表，不依赖当前时刻。

-- 相对脚本自身定位 rime/lua/，无论从哪个目录运行都能找到模块
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/../rime/lua/?.lua;" .. package.path
local out = {}
function Candidate(type_, s, e, text, comment)
  return { type = type_, start = s, _end = e, text = text, comment = comment }
end
function yield(c) out[#out + 1] = c end
local function seg(tags) return { start = 1, _end = 3, has_tag = function(_, t) return tags[t] == true end } end
local function env(tagcfg)
  return { engine = { schema = { config = { get_string = function(_, k) return k == "datetime/tag" and tagcfg or nil end } } } }
end
local fails = 0
local function check(cond, msg) if cond then print("  ✅ " .. msg) else fails = fails + 1; print("  ❌ " .. msg) end end

local M = require("datetime")
local e = env(nil); M.init(e)
check(e.tag == "pinyin_hint", "默认 tag = pinyin_hint")

-- 触发词 & 候选数
local expect = { rq = 6, sj = 4, dt = 4, xq = 4, ts = 2 }
for k, n in pairs(expect) do
  out = {}; M.func(k, seg({ pinyin_hint = true }), e)
  check(#out == n, string.format("z%s → %d 个候选", k, n))
  for i, c in ipairs(out) do
    if c.quality ~= 1000 - i then check(false, string.format("%s 第 %d 个候选 quality=%s，应为 %d", k, i, tostring(c.quality), 1000 - i)) end
    if c.text == nil or c.text == "" then check(false, k .. " 第 " .. i .. " 个候选文本为空") end
  end
end

out = {}; M.func("rq", seg({ pinyin_hint = true }), e)
local desc = true
for i = 2, #out do if not (out[i].quality < out[i-1].quality) then desc = false end end
check(desc and out[#out].quality > 100, "quality 严格递减且远高于拼音候选（最低 " .. out[#out].quality .. "）")

-- 门禁
out = {}; M.func("rq", seg({ abc = true }), e);            check(#out == 0, "非 pinyin_hint 段不响应")
out = {}; M.func("xyz", seg({ pinyin_hint = true }), e);   check(#out == 0, "非触发词不产出")
local e2 = env(""); M.init(e2); out = {}; M.func("rq", seg({ abc = true }), e2)
check(#out == 6, 'tag 配为 "" 时全局响应')

-- 格式抽样（用固定时间表，不依赖当前时刻）
local B = M.builders
local t = { year = 2026, month = 9, day = 13, hour = 9, min = 5, sec = 7, wday = 7 }
local rq = B.rq(t)
check(rq[1][1] == "2026-09-13",           "rq[1] ISO 日期")
check(rq[2][1] == "2026年9月13日",         "rq[2] 中文日期不补零")
check(rq[4][1] == "20260913",             "rq[4] 紧凑")
check(rq[6][1] == "二〇二六年九月十三日",   "rq[6] 中文大写年月日: " .. rq[6][1])
local sj = B.sj(t)
check(sj[1][1] == "09:05",                "sj[1] 补零时分")
check(sj[3][1] == "9点05分",              "sj[3] 中文时分")
check(sj[4][1] == "上午9:05",              "sj[4] 时段+12小时制: " .. sj[4][1])
check(B.sj({hour=0,min=1,sec=0})[4][1] == "凌晨12:01",  "0 点 → 凌晨12")
check(B.sj({hour=12,min=0,sec=0})[4][1] == "中午12:00", "12 点 → 中午12")
check(B.sj({hour=19,min=30,sec=0})[4][1] == "晚上7:30", "19 点 → 晚上7")
local dt = B.dt(t)
check(dt[1][1] == "2026-09-13 09:05:07",  "dt[1]")
check(dt[2][1]:match("^2026%-09%-13T09:05:07[+-]%d%d:%d%d$") ~= nil, "dt[2] ISO 8601 带冒号时区: " .. dt[2][1])
local xq = B.xq(t)
check(xq[1][1] == "星期六" and xq[2][1] == "周六" and xq[3][1] == "Saturday" and xq[4][1] == "Sat", "xq 周六四种写法")
check(B.xq({wday=1})[1][1] == "星期日",  "wday=1 → 星期日")
-- 中文数字边界：通过日期字段间接测 cn_num
local function cn(d) return B.rq({year=2026,month=1,day=d})[6][1]:match("月(.-)日") end
check(cn(1)=="一" and cn(10)=="十" and cn(11)=="十一" and cn(19)=="十九" and cn(20)=="二十" and cn(21)=="二十一" and cn(31)=="三十一",
      "cn_num 边界 1/10/11/19/20/21/31: " .. table.concat({cn(1),cn(10),cn(11),cn(19),cn(20),cn(21),cn(31)}, " "))
check(B.rq({year=2000,month=1,day=1})[6][1] == "二〇〇〇年一月一日", "cn_year 2000 → 二〇〇〇")
local ts = B.ts(t)
check(ts[1][1]:match("^%d+$") and ts[2][1] == ts[1][1] .. "000", "ts 秒/毫秒")

print(fails == 0 and "\n全部通过" or ("\n失败 " .. fails .. " 项"))
os.exit(fails)
