//
//  DYLabel.swift
//  Dystopia
//
//  Created by Allison Husain on 8/25/18.
//  Copyright © 2018 Allison Husain. All rights reserved.
//

import Foundation
import os
import UIKit

/// A representation of plain text being drawn by DYLabel
public class DYText {
    public var bounds:CGRect
    public var range:CFRange
    public init(bounds boundsIn:CGRect, range rangeIn:CFRange) {
        bounds = boundsIn
        range = rangeIn
    }
}


/// A representation of a link being drawn by DYLabel
public class DYLink:DYText {
    public var url:URL
    public init(bounds boundsIn:CGRect, url urlIn:URL, range rangeIn:CFRange) {
        url = urlIn
        super.init(bounds: boundsIn, range: rangeIn)
    }
}

/// A modified version of CATiledLayer which disables fade
class CAFastFadeTileLayer:CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval {
        return 0.0 // Normally it’s 0.25
    }
}

/// An internal data structure used for tracking and interacting with this label by Voice Over
class DYAccessibilityElement:UIAccessibilityElement {
    weak var superview:UIView?
    var boundingRect:CGRect
    
    
    /// Due to the way that iOS translates touches performed by Voice Over, it is sometimes neccesary to include additional information so that the touch can be correctly interpreted. Link for the element is included because the touch may "miss" the link if clicked using VO because VO clicks directly in the center of the rect rather than the origin
    var link:DYLink?
    
    
    init(superview superViewIn:UIView, boundingRect bound:CGRect, container:Any) {
        superview = superViewIn
        boundingRect = bound
        
        super.init(accessibilityContainer: container)
    }
    
    
    /// Fix a bizarre bug? my issue? where the calculated frame is wrong later. YOU MUST SET BOUNDING RECT and superView
    override var accessibilityFrame: CGRect {
        get {
            if let superview = superview {
                return UIAccessibility.convertToScreenCoordinates(boundingRect, in: superview)
            } else {
                return CGRect.zero
            }
        }
        set{}
    }
}



/// A custom, high performance label which provides both accessibility and FAST and ACCURATE height calculation
public class DYLabel: UIView {
    public var enableFrameDebugMode = false
    internal var dyAccessibilityElements:[DYAccessibilityElement]? = nil

    internal var links:[DYLink]? = nil
    internal var text:[DYText]? = nil
    
    private let tapGesture = UITapGestureRecognizer()
    private let holdGesture = UILongPressGestureRecognizer()
    
    
    /// Should the accessibility label be split into paragraphs for plain text? Regardless of this setting, frames will start and stop for clickable links. (in other words, this is a "read the entire thing in one go" or "read by paragraph" setting)
    public var shouldGenerateAccessibilityFramesForParagraphs:Bool = true
    
    public weak var dyDelegate:DYLinkDelegate?
    
    private let lock:UnsafeMutablePointer<os_unfair_lock>
    private func lockAssertHeld() {
        #if DEBUG
        os_unfair_lock_assert_owner(lock)
        #endif /* DEBUG */
    }
    
    private func withLock(_ block:()->()) {
        os_unfair_lock_lock(lock)
        block()
        os_unfair_lock_unlock(lock)
    }
    
    private func assertMainThread() {
        assert(Thread.isMainThread, "Must be called on the main thread")
    }
    
    //MARK: Tiling
    //This code enables the view to be drawn in the background, in tiles. Huge performance win especially on large bodies of text
    public override class var layerClass: AnyClass {
        return CAFastFadeTileLayer.self
    }
    
    
    var tiledLayer: CAFastFadeTileLayer {
        return self.layer as! CAFastFadeTileLayer
    }
    
    //ONLY ACCESS THESE VARIABLES ON THE `dataUpdateQueue`!!
    internal var __attributedText:NSAttributedString?
    
    /// Attributed text to draw
    /// Warning!! This is not guaranteed to be exactly the text that's currently display but instead what will be drawn
    public var attributedText:NSAttributedString? {
        get {
            var attributedText:NSAttributedString? = nil
            
            withLock {
                attributedText = __attributedText
            }
            
            return attributedText
        }
        
        set (input) {
            assertMainThread()
           
            var needsRedraw = false
            withLock {
                // Don't bother redrawing/invalidating all our frames if the text is exactly the same
                if (input != __attributedText) {
                    needsRedraw  = true
                    __attributedText = input
                }
            }
            
            if needsRedraw {
                self.setNeedsDisplay()
            }
        }
    }
    
    internal var __backgroundColor:UIColor? = UIColor.white
    
    /// The background color, non-transparent. This is guaranteed to be up to date
    public override var backgroundColor: UIColor? {
        set (color) {
            assertMainThread()

            super.backgroundColor = color
            
            withLock {
                __backgroundColor = color
            }
        }
        
        get {
            return super.backgroundColor
        }
    }
    
    internal var __frame:CGRect = CGRect.zero
    /// The frame. This is guaranteed to be up to date however it is not guaranteed that this value will be the actual drawn size as the frame is redrawn in the background. This may seem like an error however it is important for layout code that the frame return what it *will be* very soon rather (after a background process) than what it currently is
    public override var frame: CGRect {
        set (frameIn) {
            assertMainThread()
            
            super.frame = frameIn
            
            updateTileSize()

            withLock {
                __frame = frameIn
            }
        }
        
        get {
            return super.frame
        }
    }
    
    internal var __screenScale:CGFloat = 0
    
    //MARK: Life cycle
    public override init(frame: CGRect) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: .init())
        super.init(frame: frame)
        setupViews()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: .init())
        super.init(coder: aDecoder)
        setupViews()
    }
    
    /// Create a DTLabel, the suggested way
    ///
    /// - Parameters:
    ///   - attributedTextIn: Attributed string to display
    ///   - backgroundColorIn: The background color to use. If a background color is set, blending can be disabled which gives a performance boost
    ///   - frame: The frame
    public convenience init(attributedText attributedTextIn:NSAttributedString, backgroundColor backgroundColorIn:UIColor?, frame:CGRect) {
        self.init(frame: frame)
        self.attributedText = attributedTextIn
        
        backgroundColor = backgroundColorIn
        setupViews()
    }
    
    func setupViews() {
        tiledLayer.levelsOfDetail = 1
        tiledLayer.contentsScale = 1
        
        isUserInteractionEnabled = true
        tapGesture.addTarget(self, action: #selector(DYLabel.labelTapped(_:)))
        holdGesture.addTarget(self, action: #selector(DYLabel.labelHeld(_:)))
        addGestureRecognizer(tapGesture)
        addGestureRecognizer(holdGesture)
        if (backgroundColor == nil) {
            self.isOpaque = false
        }
    }
    
    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        
        updateTileSize()
        
        withLock {
            if let screen = window?.screen {
                __screenScale = screen.scale
            } else {
                __screenScale = 1
            }
        }
    }
    
    func updateTileSize() {
        // At it's core, we're not interested in actually tiling text render.
        // This is because CoreText doesn't really offer anything in the way of parallelism as we'd effectively need to typeset on every thread individually, which is unhelpful.
        // As such, we request a tile size such that we should draw only once.
        // We can still have multiple draw requests if the tile becomes too large for the system, but this generally only happens once the tile is larger than the screen, so it's mostly fine to split these renders.
        let screenScale:CGFloat = self.window?.screen.scale ?? 1
        tiledLayer.tileSize = CGSize.init(width: frame.width * screenScale,
                                          height: frame.height * screenScale)
    }
    
    //MARK: Interaction
    @objc func labelTapped(_ gesture: UITapGestureRecognizer) {
        if let link = linkAt(point: gesture.location(in: gesture.view)) {
            dyDelegate?.didClickLink(label: self, link: link)
        }
    }
    
    @objc func labelHeld(_ gesture:UILongPressGestureRecognizer) {
        //cancel the touch, for whatever reason we keep getting events after we present another view on top
        gesture.isEnabled.toggle()
        if let link = linkAt(point: gesture.location(in: gesture.view)) {
            dyDelegate?.didLongPressLink(label: self, link: link)
        }
    }
    
    
    func newAccessibilityElement(frame:CGRect, label:String, isPlainText:Bool, linkItem:DYLink? = nil) -> DYAccessibilityElement {
        assertMainThread()
        
        let accessibilityElement = DYAccessibilityElement.init(superview: self, boundingRect: frame, container: self)
        accessibilityElement.accessibilityValue = label
        accessibilityElement.accessibilityTraits = isPlainText ? UIAccessibilityTraits.staticText : UIAccessibilityTraits.link
        accessibilityElement.link = linkItem
        
        return accessibilityElement
    }
    
    
    /// Calculate the frames of plain text, links, and accessibility elements (if needed)
    /// THIS IS AN EXPENSIVE OPERATION, especially if voice over is running. This method will attempt to skip itself automatically. If new data must be feteched, call `invalidate()`
    func fetchAttributedRectsIfNeeded() {
        assertMainThread()
        
        if links == nil ||
            (UIAccessibility.isVoiceOverRunning && dyAccessibilityElements == nil) ||
            enableFrameDebugMode {
            guard let attributedText = attributedText else { return }
            links = []
            text = []
            dyAccessibilityElements = []
            
            if bounds.size.height == 0 {
                return
            }

            UIGraphicsBeginImageContext(bounds.size)
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            let _ = DYLabel.textFrameset(attributedText: attributedText, layoutRect: bounds) { textPosition, line, attributes, run in
                let ctRect = DYLabel.getCTRectFor(run: run, line: line, origin: textPosition, context: ctx)
                let runBounds = convertCTRectToUI(rect: ctRect)
                
                let runRange = CTRunGetStringRange(run)
                if let urlAny = attributes[NSAttributedString.Key.link] {
                    if let url = urlAny as? URL {
                        links!.append(DYLink.init(bounds: runBounds, url: url, range: runRange))
                    } else if let urlString = urlAny as? String,
                              let url = URL.init(string: urlString) {
                        links!.append(DYLink.init(bounds: runBounds, url: url, range: runRange))
                    }
                } else {
                    text!.append(DYText.init(bounds: runBounds, range: runRange))
                }
            }
            UIGraphicsEndImageContext()
            
            //Accessibility element generation
            //
            /// WARNING! THIS SUBROUTINE IS VERY EXPENSIVE! It compacts links and texts into a single array, sorts it (as the links and text arrays are not exactly "sorted"), and then generates new accessibility objects)
            //
            
            var items:[DYText] = links! + text!
            items.sort { (a, b) -> Bool in
                return a.range.location < b.range.location
            }
            
            let textContent = attributedText.string as NSString
            var lastIsText:Bool = (items.first is DYLink) == false
            var frames:[CGRect] = []
            var frameLabel = ""
            var lastLinkItem:DYLink? = items.first as? DYLink
            var nextItemIsNewParagraph:Bool = false
            
            for item in items {
                let currentIsText = (item is DYLink) == false
                //if shouldDYLabelParseIntoParagraphs is false, short-circuit the paragraph split mode so the entire thing (except links) is read in one go
                if lastIsText != currentIsText || (nextItemIsNewParagraph && shouldGenerateAccessibilityFramesForParagraphs) {
                    nextItemIsNewParagraph = false
                    //We've changed frames, commit accessibility element
                    if var finalRect = frames.first {
                        for rect in frames {
                            finalRect = finalRect.union(rect)
                        }
                        if frameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                            dyAccessibilityElements?.append(newAccessibilityElement(frame: finalRect, label: frameLabel, isPlainText: lastIsText, linkItem: lastLinkItem))
                        }
                    }
                    
                    lastIsText = currentIsText
                    lastLinkItem = item as? DYLink
                    frameLabel = ""
                    frames = []
                }
                
                nextItemIsNewParagraph = textContent.substring(with: NSRange.init(location: item.range.location, length: item.range.length)).contains("\n")
                frameLabel.append(textContent.substring(with: NSRange.init(location: item.range.location, length: item.range.length)))
                frames.append(item.bounds)
            }
            
            if frameLabel.isEmpty == false {
                //Commit all remaining
                if var finalRect = frames.first {
                    for rect in frames {
                        finalRect = finalRect.union(rect)
                    }
                    if frameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        dyAccessibilityElements?.append(newAccessibilityElement(frame: finalRect, label: frameLabel, isPlainText: lastIsText, linkItem: lastLinkItem))
                    }
                }
            }
        }
    }
    
    
    /// Get the link (if any) at a given point. Useful for hit detection.
    /// Note, this method will be slightly dishonest and return links that are not *exactly* at the point if VoiceOver is running. This is to patch beavhior of the VO engine's clicking
    ///
    /// - Parameter point: The point, relative to us (x:0, y:0 is top left of textview)
    /// - Returns: A link if there is one.
    func linkAt(point:CGPoint) -> DYLink? {
        fetchAttributedRectsIfNeeded()
        for link in links! {
            if link.bounds.contains(point) {
                return link
            }
        }
        
        //Voiceover doesn't always click "right" on the link but instead on the center of the rect. If VO is running, relax the hit box
        if (UIAccessibility.isVoiceOverRunning) {
            for accessibilityItem in dyAccessibilityElements! {
                if let link = accessibilityItem.link, accessibilityItem.boundingRect.contains(point) {
                    return link
                }
            }
        }
        return nil
    }
    
    //MARK: Accessibility
    public override var isAccessibilityElement: Bool {
        get {
            return false
        }
        
        set { }
    }
    
    public override var accessibilityFrame: CGRect {
        get {
            if let superview = superview {
                return UIAccessibility.convertToScreenCoordinates(self.bounds, in: superview)
            } else {
                return CGRect.zero
            }
        }
        
        set { }
    }
    
    public override func accessibilityElementCount() -> Int {
        fetchAttributedRectsIfNeeded()
        return dyAccessibilityElements?.count ?? 0
    }
    
    public override func accessibilityElement(at index: Int) -> Any? {
        fetchAttributedRectsIfNeeded()
        if (index >= dyAccessibilityElements?.count ?? 0) {
            return nil
        }
        
        return dyAccessibilityElements?[index]
    }
    
    public override func index(ofAccessibilityElement element: Any) -> Int {
        fetchAttributedRectsIfNeeded()
        
        guard let item = element as? DYAccessibilityElement else {
            return -1
        }
        
        return dyAccessibilityElements?.firstIndex(of: item) ?? -1
    }
    
    public override var accessibilityElements: [Any]? {
        get {
            fetchAttributedRectsIfNeeded()
            return dyAccessibilityElements
        }
        
        set { }
    }
    
    //MARK: Rendering, sizing
    
    /// Converts a CT rect (0,0 is bottom left) to UI rect (0,0 is top left)
    ///
    /// - Parameter rect: In rect, CT style
    /// - Returns: UI style
    func convertCTRectToUI(rect:CGRect) -> CGRect {
        return CGRect.init(x: rect.minX, y: self.bounds.size.height - rect.maxY, width: rect.size.width, height: rect.size.height)
    }
    
    
    /// Get the CoreText relative frame for a given CTRun. This method works around an iOS <=10 CoreText bug in CTRunGetImageBounds
    /// https://stackoverflow.com/q/52030633/1166266
    ///
    /// - Parameters:
    ///   - run: The run
    ///   - context: Context, used by CTRunGetImageBounds
    /// - Returns: A tight fitting, CT rect that fits around the run
    private static func getCTRectFor(run:CTRun, line:CTLine,origin:CGPoint,context:CGContext) -> CGRect {
        var a:CGFloat = 0
        var d:CGFloat = 0
        var l:CGFloat = 0
        let width = CTRunGetTypographicBounds(run, CFRange.init(location: 0, length: 0), &a, &d, &l)
        
        let q = CTRunGetStringRange(run)
        let xOffset = CTLineGetOffsetForStringIndex(line, q.location, nil)
        
        var boundT = CGRect.zero
        boundT.size.width = CGFloat(width)
        boundT.size.height = a + d
        boundT.origin.x = origin.x + CGFloat(xOffset)
        boundT.origin.y = origin.y
        boundT.origin.y -= d
        
        return boundT
    }
    
    public override func setNeedsLayout() {
        super.setNeedsLayout()
        invalidate()
    }
    
    public override func setNeedsDisplay() {
        super.setNeedsDisplay()
        invalidate()
    }
    
    /// Invalidate link, text, and accessibility caches
    func invalidate() {
        assertMainThread()
        links = nil
        text = nil
        dyAccessibilityElements = nil
    }
    
    public override func layoutSubviews() {
        setNeedsDisplay()
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        // Do not call super!
        
        var drawBackgroundColor:CGColor = UIColor.clear.cgColor
        var drawFrame:CGRect = .zero
        var drawAttributedText:NSAttributedString? = nil
        var drawScreenScale:CGFloat = 0
       
        withLock {
            if let color = __backgroundColor {
                drawBackgroundColor = color.cgColor
            } else {
                drawBackgroundColor = UIColor.white.cgColor
            }
            
            drawFrame = __frame
            drawAttributedText = __attributedText
            drawScreenScale = __screenScale
        }
        
        let partialRect = ctx.boundingBoxOfClipPath
        
        ctx.setFillColor(drawBackgroundColor)
//        ctx.setFillColor(UIColor.init(red: partialRect.origin.x / bounds.width, green: partialRect.origin.y / bounds.height, blue: 0.7, alpha: 1).cgColor)
        ctx.fill(partialRect)
        
        ctx.textMatrix = CGAffineTransform.identity
        ctx.translateBy(x: 0, y: drawFrame.size.height)
        ctx.scaleBy(x: 1.0, y: -1.0)
        
        
        if let drawAttributedText = drawAttributedText {
            let _ = DYLabel.textFrameset(attributedText: drawAttributedText, layoutRect: drawFrame) { textPosition, line, attributesAtPosition, run in
                // TODO: We're rendering everything (even if it's outside our tile)
                // This is inefficient but it doesn't really seem to matter and I'm too tired to deal with this
                // We could skip the draw if we know that no part of it intersects our partial rect
                ctx.textPosition = textPosition
                CTRunDraw(run, ctx, CFRangeMake(0, 0))

                if attributesAtPosition.object(forKey: DYLabel.Key.FullLineUnderLine) != nil {
                    let ctRect = DYLabel.getCTRectFor(run: run, line: line, origin: textPosition, context: ctx)
                    
                    if let underlineColor = attributesAtPosition.object(forKey: DYLabel.Key.FullLineUnderLineColor) as? UIColor {
                        ctx.setStrokeColor(underlineColor.cgColor)
                    }
                    
                    let strikeYPosition = ctRect.minY
                    let scale = drawScreenScale
                    
                    let width = 1 / scale
                    let offset = width / 2
                    
                    let yFinal:CGFloat = max(strikeYPosition - offset, width)
                    ctx.setLineWidth(width)
                    
                    ctx.beginPath()
                    
                    ctx.move(to: CGPoint.init(x: 0, y: yFinal))
                    ctx.addLine(to: CGPoint.init(x: drawFrame.width, y: yFinal))
                    ctx.strokePath()
                }
            }
        }
    }
    
    private static func textFrameset(attributedText: NSAttributedString, layoutRect:CGRect, handleRun: (CGPoint, CTLine, NSDictionary, CTRun) -> ()) -> CGFloat {
        let frameSetter = CTFramesetterCreateWithAttributedString(attributedText)
        let framePath = CGPath.init(rect: layoutRect, transform: nil)
        let frameSetterFrame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), framePath, nil)
        
        //Fetch our lines, bridging to swift from CFArray
        let lines:CFArray = CTFrameGetLines(frameSetterFrame)
        let lineCount = CFArrayGetCount(lines)
        
        //Get the line origin coordinates. These are used for calculating stock line height (w/o baseline modifications)
        var lineOrigins = [CGPoint](repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frameSetterFrame, CFRangeMake(0, 0), &lineOrigins);
        
        //Since we're starting from the bottom of the container we need get our bottom offset/padding (so text isn't slammed to the bottom or cut off)
        var ascent:CGFloat = 0
        var descent:CGFloat = 0
        var leading:CGFloat = 0
        if lineCount > 0 {
            let lastLine = unsafeBitCast(CFArrayGetValueAtIndex(lines, lineCount - 1), to: CTLine.self)
            
            let lastLineRange = CTLineGetStringRange(lastLine)
            let lastDrawnLength = lastLineRange.location + lastLineRange.length
            if lastDrawnLength != attributedText.length {
                //Estimation size is too small, try again!
                #if DEBUG
                NSLog("[DYLabel Debug] textFrameset size was too small by %zu characters", attributedText.length - lastDrawnLength);
                #endif /* DEBUG */
                return -1
            }

            CTLineGetTypographicBounds(lastLine, &ascent, &descent, &leading)
        }
        
        //This variable holds the current draw position, relative to CT origin of the bottom left
        var drawYPositionFromOrigin:CGFloat = descent
        
        //Again, draw the lines in reverse so we don't need look ahead
        for lineIndex in (0..<lineCount).reversed()  {
            //Calculate the current line height so we can accurately move the position up later
            let lastLinePosition = lineIndex > 0 ? lineOrigins[lineIndex - 1].y: layoutRect.height
            let currentLineHeight = lastLinePosition - lineOrigins[lineIndex].y
            //Throughout the loop below this variable will be updated to the tallest value for the current line
            var maxLineHeight:CGFloat = currentLineHeight
            
            //Grab the current run glyph. This is used for attributed string interop
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, lineIndex), to: CTLine.self)
            let glyphRuns = CTLineGetGlyphRuns(line)
            let glyphRunsCount = CFArrayGetCount(glyphRuns)
            
            for runIndex in 0..<glyphRunsCount {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(glyphRuns, runIndex), to: CTRun.self)
                
                let attributesAtPosition:NSDictionary = unsafeBitCast(CTRunGetAttributes(run), to: NSDictionary.self) as NSDictionary
                var baselineAdjustment: CGFloat = 0.0
                if let adjust = attributesAtPosition.object(forKey: NSAttributedString.Key.baselineOffset) as? NSNumber {
                    //We have a baseline offset!
                    baselineAdjustment = CGFloat(adjust.floatValue)
                }
                
                //Move the draw head. Note that we're drawing from the un-updated drawYPositionFromOrigin. This is again thanks to CT cartesian plane where we draw from the bottom left of text too.
                let drawXPositionFromOrigin:CGFloat = lineOrigins[lineIndex].x
                let textPosition = CGPoint.init(x: drawXPositionFromOrigin, y: drawYPositionFromOrigin)
                
                handleRun(textPosition, line, attributesAtPosition, run)
                
                //Check if this glyph run is tallest, and move it if it is
                maxLineHeight = max(currentLineHeight + baselineAdjustment, maxLineHeight)
            }
            
            //Move our position because we've completed the drawing of the line which is at most `maxLineHeight`
            drawYPositionFromOrigin += maxLineHeight
        }
        
        return drawYPositionFromOrigin
    }
    
    /// Calculate the height if it were drawn using `drawText`
    /// Uses the same code as drawText except it doesn't draw.
    ///
    /// - Parameters:
    ///   - attributedText: The text to calculate the height of
    ///   - width: The constraining width
    ///   - estimationHeight: The maximum (guessed) height of this text. If the text is taller than this, it will take multiple attempts to calculate (height doubles). There does not appear to be a performance drop for larger sizes, however the if this size is too large, older devices/iOS versions will yield invalid/too small heights due to CoreText weirdness.
    public static func size(of attributedText:NSAttributedString, width:CGFloat, estimationHeight:CGFloat = 30000) -> CGSize {
        var currentEstimationHeight:CGFloat = estimationHeight
        repeat {
            let estimationRect = CGRect.init(origin: .zero, size: .init(width: width, height: currentEstimationHeight))
            
            let textHeight = DYLabel.textFrameset(attributedText: attributedText, layoutRect: estimationRect) { _, _, _, _ in
            }
            
            if textHeight >= 0{
                return CGSize.init(width: width, height: textHeight)
            }
            
            // Estimation size was too small, bump it
            currentEstimationHeight *= 2
        } while (true)
    }
    
    public class Key {
        /// Hacky add-on to let you draw a line from the beneath  this text to from x=0 to x=max. You'll want to apply this to the line with the LOWEST baseline for proper looks
        public static let FullLineUnderLine = NSAttributedString.Key.init("DYLabel.FullLineUnderLineKey")
        public static let FullLineUnderLineColor = NSAttributedString.Key.init("DYLabel.FullLineUnderLineColorKey")
    }
}

public protocol DYLinkDelegate : class {
    func didClickLink(label: DYLabel, link:DYLink);
    func didLongPressLink(label: DYLabel, link:DYLink);
}
