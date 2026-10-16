//
//  TLocationObserve.h
//  构建模式开关（抖音版）
//

#ifndef TLocationObserve_h
#define TLocationObserve_h

// ================= 构建模式 =================
// TLO_OBSERVE_MODE = 1  → 观测版：跳过卡密门控，冷启动自动下发一个假坐标并开启 toast，
//                         用于验证「抖音的定位通道能不能被假坐标改掉」。
// TLO_OBSERVE_MODE = 0  → 正式版：走卡密门控（未激活不替换坐标、不显示悬浮球）。
#define TLO_OBSERVE_MODE 1

#endif /* TLocationObserve_h */
