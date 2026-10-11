import { accessibility } from '@kit.AccessibilityKit';
import { curves } from '@kit.ArkUI';

export class MotionService {
  static reduced(user: boolean = false): boolean {
    try { return user || accessibility.isAnimationReduceEnabledSync(); } catch { return user; }
  }
  static options(user: boolean = false): AnimateParam {
    return { duration: MotionService.reduced(user) ? 0 : 280, curve: curves.cubicBezierCurve(0.2, 0, 0.15, 1) };
  }
  static entrance(user: boolean = false): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: MotionService.reduced(user) ? 0 : 14 })).animation(MotionService.options(user));
  }
}
