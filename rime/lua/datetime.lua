-- datetime.lua —— 日期 / 时间 / 星期 / 时间戳 候选
--
-- rime-wubipinyin · Apache-2.0 · 从零实现，不含任何第三方 Lua 代码。
--
-- 触发方式：在 z 引导的拼音段里输入触发词
--   zrq  日期        zsj  时间        zdt  日期 + 时间
--   zxq  星期        zts  时间戳
--
-- 设计约束：
--   * 触发词 ≤ 3 个字母。剥掉前缀 z 后编码段长度 ≤ 3 < 4，永远不会被
--     四码上屏（speller/max_code_length）顶掉。
--   * 候选 quality 设得远高于拼音候选，稳定排在同段拼音（时间 / 世界…）之前。
--   * 不用 os.date 的 "%-m" 之类 GNU 扩展：Lua 5.4 会拒绝非 C99 的转换符，
--     macOS 的 BSD strftime 也不认。一律取 os.date("*t") 自己拼。
--   * 不用 // 整除、goto 等 5.3+ 语法，兼容按 LuaJIT / 5.1 编译的 librime-lua。

local M = {}

local CN_DIGITS = { [0] = "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
local CN_WEEK   = { "日", "一", "二", "三", "四", "五", "六" }   -- os.date wday: 1 = 周日
local EN_WEEK   = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local EN_WEEK3  = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- 年份逐位读：2026 → 二〇二六
local function cn_year(y)
  return (tostring(y):gsub("%d", function(d) return CN_DIGITS[tonumber(d)] end))
end

-- 1..31 → 一 … 九 十 十一 … 十九 二十 二十一 … 三十一
local function cn_num(n)
  if n < 10 then return CN_DIGITS[n] end
  local tens = math.floor(n / 10)
  local ones = n - tens * 10
  local s = (tens == 1) and "十" or (CN_DIGITS[tens] .. "十")
  if ones > 0 then s = s .. CN_DIGITS[ones] end
  return s
end

-- 中文时段
local function period(h)
  if h < 6  then return "凌晨" end
  if h < 9  then return "早上" end
  if h < 12 then return "上午" end
  if h < 13 then return "中午" end
  if h < 18 then return "下午" end
  return "晚上"
end

-- 时区 +0800 → +08:00（%z 是 C99 标准转换符，各平台都支持）
local function tz_colon()
  local z = os.date("%z") or ""
  return (z:gsub("^([+-]%d%d)(%d%d)$", "%1:%2"))
end

-- 每个触发词一个生成器，输入 os.date("*t") 的表，返回 { {文本, 注释}, ... }
local builders = {}

builders.rq = function(t)
  return {
    { string.format("%04d-%02d-%02d", t.year, t.month, t.day),            "〔日期〕" },
    { string.format("%d年%d月%d日",    t.year, t.month, t.day),            "〔日期〕" },
    { string.format("%04d/%02d/%02d", t.year, t.month, t.day),            "〔日期〕" },
    { string.format("%04d%02d%02d",   t.year, t.month, t.day),            "〔日期〕" },
    { string.format("%d月%d日",        t.month, t.day),                    "〔日期〕" },
    { cn_year(t.year) .. "年" .. cn_num(t.month) .. "月" .. cn_num(t.day) .. "日", "〔日期〕" },
  }
end

builders.sj = function(t)
  local h12 = t.hour % 12
  if h12 == 0 then h12 = 12 end
  return {
    { string.format("%02d:%02d",       t.hour, t.min),          "〔时间〕" },
    { string.format("%02d:%02d:%02d",  t.hour, t.min, t.sec),   "〔时间〕" },
    { string.format("%d点%02d分",      t.hour, t.min),          "〔时间〕" },
    { string.format("%s%d:%02d",       period(t.hour), h12, t.min), "〔时间〕" },
  }
end

builders.dt = function(t)
  return {
    { string.format("%04d-%02d-%02d %02d:%02d:%02d",
        t.year, t.month, t.day, t.hour, t.min, t.sec),                    "〔日期时间〕" },
    { string.format("%04d-%02d-%02dT%02d:%02d:%02d%s",
        t.year, t.month, t.day, t.hour, t.min, t.sec, tz_colon()),        "〔ISO 8601〕" },
    { string.format("%d年%d月%d日 %02d:%02d",
        t.year, t.month, t.day, t.hour, t.min),                           "〔日期时间〕" },
    { string.format("%04d%02d%02d%02d%02d%02d",
        t.year, t.month, t.day, t.hour, t.min, t.sec),                    "〔紧凑〕" },
  }
end

builders.xq = function(t)
  local w = t.wday
  return {
    { "星期" .. CN_WEEK[w], "〔星期〕" },
    { "周"   .. CN_WEEK[w], "〔星期〕" },
    { EN_WEEK[w],           "〔星期〕" },
    { EN_WEEK3[w],          "〔星期〕" },
  }
end

builders.ts = function(_)
  local s = os.time()
  return {
    { tostring(s),           "〔时间戳·秒〕" },
    { tostring(s) .. "000",  "〔时间戳·毫秒〕" },   -- Lua 没有亚秒时钟，末三位为 000
  }
end

-- 暴露给测试用
M.builders = builders

function M.init(env)
  -- 只响应带此标签的分段。默认 pinyin_hint，即 z 引导的拼音段；
  -- 在方案里设 datetime/tag 可改，设为空字符串则对所有分段生效。
  local config = env.engine.schema.config
  local tag = config:get_string("datetime/tag")
  env.tag = (tag == nil) and "pinyin_hint" or tag
end

function M.func(input, seg, env)
  if env.tag ~= "" and not seg:has_tag(env.tag) then return end
  local build = builders[input]
  if not build then return end

  local list = build(os.date("*t"))
  for i, item in ipairs(list) do
    local cand = Candidate("datetime", seg.start, seg._end, item[1], item[2])
    cand.quality = 1000 - i     -- 远高于拼音候选；递减保证内部顺序不被打乱
    yield(cand)
  end
end

return M
