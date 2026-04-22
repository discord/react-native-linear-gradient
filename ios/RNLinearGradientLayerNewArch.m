#import "RNLinearGradientLayerNewArch.h"

#include <math.h>
#import <UIKit/UIKit.h>

@implementation RNLinearGradientLayerNewArch
{
    CALayer *_clipLayer;
    CAGradientLayer *_gradientLayer;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        // _clipLayer clips the gradient to the outer bounds + cornerRadius,
        // independently of self.masksToBounds (which follows yoga overflow).
        _clipLayer = [CALayer layer];
        _clipLayer.masksToBounds = YES;
        // Push the gradient behind RN-child sublayers (default zPosition 0)
        // but in front of RCTView's private background / border / shadow
        // sublayers, which Fabric's RCTViewComponentView pins to
        // BACKGROUND_COLOR_ZPOSITION = -1024. -CGFLOAT_MAX would sit behind
        // those too, hiding the gradient whenever a consumer sets
        // `backgroundColor` or `boxShadow` on <LinearGradient>. -512 picks a
        // finite, comfortable midpoint.
        _clipLayer.zPosition = -512.0;
        [self addSublayer:_clipLayer];

        _gradientLayer = [CAGradientLayer layer];
        // Our geometry math assumes rotation pivots around the gradient
        // layer's center. CALayer's default anchorPoint is (0.5, 0.5); set
        // it explicitly so a future subclass / animator can't silently move
        // the pivot.
        _gradientLayer.anchorPoint = CGPointMake(0.5, 0.5);
        [_clipLayer addSublayer:_gradientLayer];

        #ifndef RCT_NEW_ARCH_ENABLED
        self.masksToBounds = YES;
        #endif
        _startPoint = CGPointMake(0.0, 0.0);
        _endPoint = CGPointMake(0.0, 0.0);
        _angleCenter = CGPointMake(0.0, 0.0);
        _angle = 0.0;
        _useAngle = NO;
    }

    return self;
}

- (void)layoutSublayers
{
    [super layoutSublayers];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _clipLayer.frame = self.bounds;
    [self mirrorCornerShape];
    [self applyGradientGeometry];

    [CATransaction commit];
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
    [super setCornerRadius:cornerRadius];
    // RCTView updates cornerRadius without changing bounds, so layoutSublayers
    // won't fire — mirror it onto _clipLayer immediately or the gradient clip
    // lags behind the outer view's rounded corners.
    [self mirrorCornerShape];
}

- (void)mirrorCornerShape
{
    if (!_clipLayer) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _clipLayer.cornerRadius = fmax(0.0, self.cornerRadius);
    if (@available(iOS 13.0, *)) {
        _clipLayer.cornerCurve = self.cornerCurve;
    }
    [CATransaction commit];
}

- (void)setColors:(NSArray<UIColor *> *)colors
{
    _colors = [colors copy];

    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *color in colors) {
        [cgColors addObject:(id)color.CGColor];
    }

    // _gradientLayer is a standalone sublayer (not a UIView's backing layer),
    // so CAGradientLayer's animatable `colors` uses its default implicit
    // action and crossfades on every assignment. Disable actions so JS prop
    // updates snap.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gradientLayer.colors = cgColors;
    [CATransaction commit];
}

- (void)setLocations:(NSArray<NSNumber *> *)locations
{
    _locations = [locations copy];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gradientLayer.locations = locations;
    [CATransaction commit];
}

- (void)setStartPoint:(CGPoint)startPoint
{
    _startPoint = startPoint;
    [self applyGradientGeometry];
}

- (void)setEndPoint:(CGPoint)endPoint
{
    _endPoint = endPoint;
    [self applyGradientGeometry];
}

- (void)setUseAngle:(BOOL)useAngle
{
    _useAngle = useAngle;
    [self applyGradientGeometry];
}

- (void)setAngleCenter:(CGPoint)angleCenter
{
    _angleCenter = angleCenter;
    [self applyGradientGeometry];
}

- (void)setAngle:(CGFloat)angle
{
    _angle = angle;
    [self applyGradientGeometry];
}

- (void)applyGradientGeometry
{
    CGSize size = self.bounds.size;
    CGFloat W = size.width;
    CGFloat H = size.height;

    // Bail if bounds aren't set yet — setters can fire before the first
    // layout pass. layoutSublayers will re-run geometry once W/H are real.
    if (W <= 0.0 || H <= 0.0) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (!_useAngle) {
        _gradientLayer.bounds = CGRectMake(0, 0, W, H);
        _gradientLayer.position = CGPointMake(W / 2.0, H / 2.0);
        _gradientLayer.transform = CATransform3DIdentity;
        _gradientLayer.startPoint = _startPoint;
        _gradientLayer.endPoint = _endPoint;
    } else {
        // Guard numerics: NaN propagates into every CA property and wipes
        // the gradient; large angles lose sin/cos precision via argument
        // reduction.
        CGFloat angle = isfinite(_angle) ? fmod(_angle, 360.0) : 0.0;
        CGFloat acxNorm = isfinite(_angleCenter.x) ? _angleCenter.x : 0.5;
        CGFloat acyNorm = isfinite(_angleCenter.y) ? _angleCenter.y : 0.5;

        // Render a bearing-0 (pointing-up / north) gradient in a square
        // sublayer and rotate it into place, rather than letting
        // CAGradientLayer handle the angle directly. CAGradientLayer's
        // iso-color lines are perpendicular to startPoint→endPoint in
        // unit space, which on a non-square layer gets stretched under the
        // unit→pixel mapping and compresses the visible t-range. A square
        // layer has W = H, so perpendicular-in-unit-space stays
        // perpendicular-in-pixel-space after the rotation transform.
        CGFloat bearingRad = angle * M_PI / 180.0;
        // Half the projection of the parent rectangle onto the bearing
        // direction — i.e., the CSS-spec distance from the rectangle's
        // center to the 0% / 100% stop along the gradient line. Note this
        // uses the rectangle's geometric center, not angleCenter, matching
        // the CSS `linear-gradient` spec (which has no angleCenter concept).
        CGFloat halfExtent = (W * fabs(sin(bearingRad)) + H * fabs(cos(bearingRad))) / 2.0;

        // The square must cover every parent corner in the rotated
        // frame. A corner at (cx, cy) relative to angleCenter projects
        // to (x', y') on the rotated axes; we need both |x'| and |y'|
        // ≤ layerSize/2. Taking the max over all four corners of
        // max(|x'|, |y'|) and doubling gives the tight square size.
        // This is tighter than 2·√(x'² + y'²) (the distance bound) by
        // up to ~3% linear at 45°; exact at axis angles. The +2 is
        // slack for sub-pixel round-off at exact-fit angles.
        CGFloat acx = acxNorm * W;
        CGFloat acy = acyNorm * H;
        CGFloat cosA = cos(bearingRad);
        CGFloat sinA = sin(bearingRad);
        CGFloat cornerDx[4] = { -acx, W - acx, -acx, W - acx };
        CGFloat cornerDy[4] = { -acy, -acy, H - acy, H - acy };
        CGFloat maxHalf = 0.0;
        for (int i = 0; i < 4; i++) {
            CGFloat xp = cornerDx[i] * cosA + cornerDy[i] * sinA;
            CGFloat yp = -cornerDx[i] * sinA + cornerDy[i] * cosA;
            maxHalf = fmax(maxHalf, fmax(fabs(xp), fabs(yp)));
        }
        CGFloat layerSize = 2.0 * maxHalf + 2.0;

        // Pin startPoint / endPoint to ±halfExtent pixels from the layer's
        // center regardless of layerSize. That nails the 0% and 100% stops
        // to the CSS-spec pixel offset from angleCenter; the layer itself
        // is free to extend past the parent for full coverage.
        // startPoint is the 0% stop (below center), endPoint the 100% stop
        // (above center). Rotating a north-pointing gradient by `_angle`
        // degrees clockwise produces the bearing direction directly — no
        // offset needed.
        CGFloat ratio = halfExtent / layerSize;
        _gradientLayer.bounds = CGRectMake(0, 0, layerSize, layerSize);
        _gradientLayer.position = CGPointMake(acx, acy);
        _gradientLayer.startPoint = CGPointMake(0.5, 0.5 + ratio);
        _gradientLayer.endPoint = CGPointMake(0.5, 0.5 - ratio);
        _gradientLayer.transform = CATransform3DMakeRotation(bearingRad, 0, 0, 1);
    }

    [CATransaction commit];
}

@end
