---
id: SXX
title: 一句话标题
milestone: M?
status: todo
depends_on: []
estimate_days: 1
plan_refs: []   # 01-implementation-plan.md 的章节，如 §5.2
ui_refs: []     # 02-ui-spec.md 的章节 / 元素编号，如 §8 P5
---

# SXX 标题

## 目标
一段话：做完后用户 / 下一个 spec 能得到什么。

## 范围
### 做
- …
### 不做（留给谁）
- …（→ SYY）

## 交付物
- `KnowingYou/…/Foo.swift`
- 测试：`KnowingYouTests/FooTests.swift`

## 接口 / 契约
本 spec 对外暴露、其他 spec 会依赖的类型与方法签名。与 S00 冲突时以 S00 为准并去改 S00。

## 实现要点
只写非显而易见的、容易踩坑的、必须遵守的。

## 验收标准
- [ ] 可逐条核对的、二值的判定。手工项写清操作与预期。

## 测试
单元测试覆盖什么；手工测试怎么做。

## 决策记录
| 日期 | 决定 | 原因 |
|---|---|---|
