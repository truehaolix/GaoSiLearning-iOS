#import "GSCropOverlayView.h"

@interface GSCropOverlayView ()
@property (nonatomic, strong) NSMutableArray<NSValue *> *candidates;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *selectedIndices;
@property (nonatomic, assign) NSInteger activeDraggingIndex;
@property (nonatomic, assign) CGPoint dragStartPoint;
@property (nonatomic, assign) CGRect dragInitialRect;
@end

@implementation GSCropOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _candidates = [NSMutableArray array];
        _selectedIndices = [NSMutableSet set];
        _activeDraggingIndex = -1;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)setCandidateBoxes:(NSArray<NSValue *> *)boxes {
    [_candidates removeAllObjects];
    [_selectedIndices removeAllObjects];
    [_candidates addObjectsFromArray:boxes];
    // 默认选中第一题
    if (_candidates.count > 0) {
        [_selectedIndices addObject:@(0)];
    }
    [self setNeedsDisplay];
    [self notifyDelegate];
}

- (NSArray<NSValue *> *)selectedBoxes {
    NSMutableArray<NSValue *> *res = [NSMutableArray array];
    for (NSNumber *idx in _selectedIndices) {
        NSInteger i = [idx integerValue];
        if (i >= 0 && i < (NSInteger)_candidates.count) {
            [res addObject:_candidates[i]];
        }
    }
    return [res copy];
}

- (void)clearSelection {
    [_selectedIndices removeAllObjects];
    [self setNeedsDisplay];
    [self notifyDelegate];
}

- (void)selectAllBoxes {
    for (NSInteger i = 0; i < (NSInteger)_candidates.count; ++i) {
        [_selectedIndices addObject:@(i)];
    }
    [self setNeedsDisplay];
    [self notifyDelegate];
}

- (void)notifyDelegate {
    if ([self.delegate respondsToSelector:@selector(cropOverlayDidUpdateSelection:)]) {
        [self.delegate cropOverlayDidUpdateSelection:[self selectedBoxes]];
    }
}

#pragma mark - 坐标变换 (AspectFit 映射)

- (CGRect)imageDisplayRect {
    if (self.imageSize.width <= 0 || self.imageSize.height <= 0) return self.bounds;
    CGFloat viewW = self.bounds.size.width;
    CGFloat viewH = self.bounds.size.height;
    CGFloat imgW = self.imageSize.width;
    CGFloat imgH = self.imageSize.height;

    CGFloat scale = MIN(viewW / imgW, viewH / imgH);
    CGFloat dw = imgW * scale;
    CGFloat dh = imgH * scale;
    CGFloat dx = (viewW - dw) / 2.0;
    CGFloat dy = (viewH - dh) / 2.0;

    return CGRectMake(dx, dy, dw, dh);
}

- (CGRect)viewRectFromNormalizedRect:(CGRect)normRect {
    CGRect disp = [self imageDisplayRect];
    return CGRectMake(disp.origin.x + normRect.origin.x * disp.size.width,
                      disp.origin.y + normRect.origin.y * disp.size.height,
                      normRect.size.width * disp.size.width,
                      normRect.size.height * disp.size.height);
}

- (CGRect)normalizedRectFromViewRect:(CGRect)viewRect {
    CGRect disp = [self imageDisplayRect];
    if (disp.size.width <= 0 || disp.size.height <= 0) return CGRectZero;
    CGFloat nx = (viewRect.origin.x - disp.origin.x) / disp.size.width;
    CGFloat ny = (viewRect.origin.y - disp.origin.y) / disp.size.height;
    CGFloat nw = viewRect.size.width / disp.size.width;
    CGFloat nh = viewRect.size.height / disp.size.height;
    return CGRectMake(MAX(0, MIN(1, nx)),
                      MAX(0, MIN(1, ny)),
                      MAX(0.01, MIN(1, nw)),
                      MAX(0.01, MIN(1, nh)));
}

#pragma mark - 绘图渲染

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    for (NSInteger i = 0; i < (NSInteger)_candidates.count; ++i) {
        CGRect norm = [_candidates[i] CGRectValue];
        CGRect vRect = [self viewRectFromNormalizedRect:norm];
        BOOL isSelected = [_selectedIndices containsObject:@(i)];

        if (isSelected) {
            // 选中的题框：高亮翡翠绿
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:0.15].CGColor);
            CGContextFillRect(ctx, vRect);

            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0].CGColor);
            CGContextSetLineWidth(ctx, 2.5);
            CGContextStrokeRect(ctx, vRect);

            // 角标：题 1 / 题 2
            NSString *tag = [NSString stringWithFormat:@"题 %ld (已选)", (long)(i + 1)];
            [self drawTag:tag atPoint:vRect.origin backgroundColor:[UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:0.95]];
        } else {
            // 未选中的题框：深海蓝虚线
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:0.85].CGColor);
            CGContextSetLineWidth(ctx, 1.5);
            CGFloat lengths[] = {6.0, 4.0};
            CGContextSetLineDash(ctx, 0, lengths, 2);
            CGContextStrokeRect(ctx, vRect);
            CGContextSetLineDash(ctx, 0, NULL, 0);

            NSString *tag = [NSString stringWithFormat:@"题 %ld", (long)(i + 1)];
            [self drawTag:tag atPoint:vRect.origin backgroundColor:[UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:0.85]];
        }
    }
}

- (void)drawTag:(NSString *)text atPoint:(CGPoint)pt backgroundColor:(UIColor *)bgColor {
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    CGSize txtSize = [text sizeWithAttributes:attrs];
    CGRect tagRect = CGRectMake(pt.x, pt.y - 18, txtSize.width + 12, 18);
    if (tagRect.origin.y < 0) tagRect.origin.y = pt.y;

    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:tagRect cornerRadius:4];
    [bgColor setFill];
    [path fill];

    [text drawInRect:CGRectMake(tagRect.origin.x + 6, tagRect.origin.y + 2, txtSize.width, txtSize.height) withAttributes:attrs];
}

#pragma mark - 触摸与交互

- (void)handleTap:(UITapGestureRecognizer *)tap {
    CGPoint loc = [tap locationInView:self];
    // 逆序查找击中哪个题框
    for (NSInteger i = (NSInteger)_candidates.count - 1; i >= 0; --i) {
        CGRect vRect = [self viewRectFromNormalizedRect:[_candidates[i] CGRectValue]];
        CGRect hitRect = CGRectInset(vRect, -10, -10);
        if (CGRectContainsPoint(hitRect, loc)) {
            if ([_selectedIndices containsObject:@(i)]) {
                [_selectedIndices removeObject:@(i)];
            } else {
                [_selectedIndices addObject:@(i)];
            }
            [self setNeedsDisplay];
            [self notifyDelegate];
            return;
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint loc = [pan locationInView:self];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _activeDraggingIndex = -1;
        for (NSInteger i = (NSInteger)_candidates.count - 1; i >= 0; --i) {
            CGRect vRect = [self viewRectFromNormalizedRect:[_candidates[i] CGRectValue]];
            if (CGRectContainsPoint(vRect, loc)) {
                _activeDraggingIndex = i;
                _dragStartPoint = loc;
                _dragInitialRect = vRect;
                [_selectedIndices addObject:@(i)];
                break;
            }
        }
    } else if (pan.state == UIGestureRecognizerStateChanged && _activeDraggingIndex >= 0) {
        CGFloat dx = loc.x - _dragStartPoint.x;
        CGFloat dy = loc.y - _dragStartPoint.y;
        CGRect newVRect = CGRectOffset(_dragInitialRect, dx, dy);
        CGRect newNorm = [self normalizedRectFromViewRect:newVRect];
        _candidates[_activeDraggingIndex] = [NSValue valueWithCGRect:newNorm];
        [self setNeedsDisplay];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        _activeDraggingIndex = -1;
        [self notifyDelegate];
    }
}

@end
