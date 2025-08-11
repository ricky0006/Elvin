## SMC Limit EA (MQL5)

Expert Advisor that places Buy Limit and Sell Limit orders on Smart Money Concepts (SMC) Order Blocks after a Break Of Structure (BOS). Includes risk-based position sizing, spread/session filters, break-even and optional ATR trailing. Tuned defaults for XAUUSD (Gold).

### Install
- Copy `experts/SMC_Limit_EA.mq5` to your `MQL5/Experts` folder.
- Compile in MetaEditor 5.
- Attach to a chart (recommended: `XAUUSD`, `M15`).

### Inputs (key)
- `Symbol` (empty = current chart)
- `Timeframe` (analysis TF, default M15)
- `SwingLeftRight` (pivot detection tightness, 3–5 is typical for M15)
- `OBLookbackBars` (how far back to find the last opposite candle before BOS)
- `BOSBufferPoints` (buffer beyond swing to confirm BOS)
- `EntryRefinePercent` (entry within OB range; 50 = mid/mitigation)
- Risk: `RiskPercent`, `RiskRR`, `ATRPeriod`, `ATRSpecSLMultiplier`
- Limits: `MaxPendingPerDirection`, `CooldownBars`, `MinDistancePoints`, `MaxSpreadPoints`
- Session: `UseSessionFilter`, `SessionStartHour`, `SessionEndHour`
- Management: `UseBreakEven`, `BreakEvenOffsetPoints`, `UseTrailingATR`, `TrailingATRMul`
- `MagicNumber`, `OrderComment`

### Strategy logic (simplified)
1. Detect recent swing high/low using `SwingLeftRight`.
2. Confirm BOS when last closed bar closes beyond the swing by `BOSBufferPoints`.
3. Identify the last opposite candle prior to BOS as the Order Block (OB).
   - Bullish BOS → last bearish candle (OB zone: open to low)
   - Bearish BOS → last bullish candle (OB zone: open to high)
4. Entry is refined to `EntryRefinePercent` of the OB range (50% by default).
5. Place Buy Limit/Sell Limit at entry with SL beyond the OB (optionally add ATR buffer) and TP by `RiskRR`.
6. Pending orders are placed as GTC (good-til-cancelled) to avoid end-of-day expiry.
7. Manage open trades with break-even at 1R and optional ATR trailing.

### Suggested settings for XAUUSD (Gold)
- Chart/TF: `M15`
- `SwingLeftRight`: 3–5
- `OBLookbackBars`: 20–30
- `BOSBufferPoints`: 80–120 (broker-dependent; for 3-digit points on gold adjust accordingly)
- `EntryRefinePercent`: 50
- `RiskPercent`: 0.5–1.0
- `RiskRR`: 2.0–3.0
- `MaxSpreadPoints`: set to your broker typical + headroom (e.g., 250 points)
- `MinDistancePoints`: 100–200 to avoid too-close pendings
- `ATRSpecSLMultiplier`: 0.0–0.5 depending on noise
- Sessions: enable London/NY overlap hours if desired (e.g., 6–22 broker time)

Note: Point size varies across brokers for XAUUSD (e.g., 2 or 3 decimal digits). Adjust `BOSBufferPoints`, `MinDistancePoints`, and `MaxSpreadPoints` to your broker's quote format.

### Notes
- The SMC detection here is pragmatic: swing-based BOS and last opposite candle OB. You can further refine (fair value gap confluence, premium/discount, higher-timeframe bias) if needed.
- Use on demo first. Performance depends on broker feed and execution.

### Changelog
- v1.0: Initial release