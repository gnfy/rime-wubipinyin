-- rime.lua —— librime-lua 入口
--
-- 这里用「rime.lua + require」而不是 lua_translator@*datetime 的新式写法：
-- Linux 发行版里打包的旧版 librime-lua 只认前者，而新版两种都支持。
--
-- 模块本体在 lua/ 目录，librime-lua 会自动把它加进 package.path。

datetime = require("datetime")
