//
//  DYLabel.swift
//  Dystopia
//
//  Created by Salman Husain on 8/25/18.
//  Copyright © 2018 Salman Husain. All rights reserved.
//

import Foundation


/// A representation of plain text being drawn by DYLabel
class DYText {
    var bounds:CGRect
    var range:CFRange
    init(bounds boundsIn:CGRect, range rangeIn:CFRange) {
        bounds = boundsIn
        range = rangeIn
    }
}


/// A representation of a link being drawn by DYLabel
class DYLink:DYText {
    var url:URL
    init(bounds boundsIn:CGRect, url urlIn:URL, range rangeIn:CFRange) {
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
            }else {
                return CGRect.zero
            }
        }
        set{}
    }
}



/// A custom, high performance label which provides both accessibility and FAST and ACCURATE height calculation
class DYLabel: UIView {
    internal var __accessibilityElements:[DYAccessibilityElement]? = nil
    var __enableFrameDebugMode = false

    
    var links:[DYLink]? = nil
    var text:[DYText]? = nil
    
    private let tapGesture = UITapGestureRecognizer()
    private let holdGesture = UILongPressGestureRecognizer()
    
    
    /// Should the accessibility label be split into paragraphs for plain text? Regardless of this setting, frames will start and stop for clickable links. (in other words, this is a "read the entire thing in one go" or "read by paragraph" setting)
    public var shouldGenerateAccessibilityFramesForParagraphs:Bool = true
    
    public weak var dyDelegate:DYLinkDelegate?
    
    
    /// This is the queue used for reading and writing all __variables! DO NOT MODIFY THESE VALUES OUTSIDE OF THIS QUEUE!
    internal let dataUpdateQueue:DispatchQueue? = DispatchQueue(label:"DYLabel-data-update-queue",qos:.userInteractive)
    
    //MARK: Tiling
    //This code enables the view to be drawn in the background, in tiles. Huge performance win especially on large bodies of text
    override class var layerClass: AnyClass {
        return CAFastFadeTileLayer.self
    }
    
    
    var tiledLayer: CAFastFadeTileLayer {
        return self.layer as! CAFastFadeTileLayer
    }
    
    //ONLY ACCESS THESE VARIABLES ON THE `dataUpdateQueue`!!
    internal var __attributedText:NSAttributedString?
    internal var mainThreadAttributedText:NSAttributedString?
    internal var __frameSetter:CTFramesetter?
    
    /// Attributed text to draw
    /// Warning!! This is not guaranteed to be exactly the text that's currently display but instead what will be drawn
    var attributedText:NSAttributedString? {
        get {
            return mainThreadAttributedText
        }
        
        set (input) {
            if mainThreadAttributedText == input {
                //don't bother redrawing/invalidating all our frames if the text is exactly the same
                return
            }
            mainThreadAttributedText = input
            dataUpdateQueue?.async {
                self.__attributedText = input
                //invalidate the frame as we've reset
                self.__frameSetter = nil
                self.__frameSetterFrame = nil
            }
            self.setNeedsDisplay()
        }
    }
    internal var __backgroundColor:UIColor? = UIColor.white
    
    /// The background color, non-transparent. This is guaranteed to be up to date
    override var backgroundColor: UIColor? {
        set (color) {
            super.backgroundColor = color
            dataUpdateQueue?.async {
                self.__backgroundColor = color?.copy() as? UIColor
            }
        }
        
        get {
            return super.backgroundColor
        }
    }
    
    internal var __frame:CGRect = CGRect.zero
    internal var __frameSetterFrame:CTFrame?
    /// The frame. This is guaranteed to be up to date however it is not guaranteed that this value will be the actual drawn size as the frame is redrawn in the background. This may seem like an error however it is important for layout code that the frame return what it *will be* very soon rather (after a background process) than what it currently is
    override var frame: CGRect {
        set (frameIn) {
            super.frame = frameIn
            let screenHeight = UIScreen.main.bounds.height
            let height = min(frameIn.height, screenHeight)
            tiledLayer.tileSize = CGSize.init(width: frameIn.width, height: height)
            
            dataUpdateQueue?.async {
                self.__frame = frameIn
                
                //invalidate old frame
                self.__frameSetterFrame = nil
            }
        }
        
        get {
            return super.frame
        }
    }
    
    
    //MARK: Life cycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupViews()
    }
    /// Create a DTLabel, the suggested way
    ///
    /// - Parameters:
    ///   - attributedTextIn: Attributed string to display
    ///   - backgroundColorIn: The background color to use. If a background color is set, blending can be disabled which gives a performance boost
    ///   - frame: The frame
    convenience init(attributedText attributedTextIn:NSAttributedString, backgroundColor backgroundColorIn:UIColor?, frame:CGRect) {
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
    
    
    func newAccessibilityElement(frame:CGRect,label:String,isPlainText:Bool,linkItem:DYLink? = nil) -> DYAccessibilityElement {
        let accessibilityElement = DYAccessibilityElement.init(superview: self, boundingRect: frame, container: self)
        accessibilityElement.accessibilityValue = label
        accessibilityElement.accessibilityTraits = isPlainText ? UIAccessibilityTraits.staticText : UIAccessibilityTraits.link
        accessibilityElement.link = linkItem
        
        
        return accessibilityElement
    }
    
    
    /// Calculate the frames of plain text, links, and accessibility elements (if needed)
    /// THIS IS AN EXPENSIVE OPERATION, especially if voice over is running. This method will attempt to skip itself automatically. If new data must be feteched, call `invalidate()`
    func fetchAttributedRectsIfNeeded() {
        dataUpdateQueue?.sync {
            if links == nil || ( UIAccessibility.isVoiceOverRunning && __accessibilityElements == nil) || self.__enableFrameDebugMode {
                guard let attributedText = attributedText else {return}
                generateCoreTextCachesIfNeeded()

                UIGraphicsBeginImageContext(self.bounds.size)
                guard let context = UIGraphicsGetCurrentContext() else {return}
                drawText(attributedText: attributedText, shouldDraw: false, context: context, layoutRect: bounds, shouldStoreFrames: true)
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
                                __accessibilityElements?.append(newAccessibilityElement(frame: finalRect, label: frameLabel, isPlainText: lastIsText, linkItem: lastLinkItem))
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
                            __accessibilityElements?.append(newAccessibilityElement(frame: finalRect, label: frameLabel, isPlainText: lastIsText, linkItem: lastLinkItem))
                        }
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
            for accessibilityItem in __accessibilityElements! {
                if let link = accessibilityItem.link, accessibilityItem.boundingRect.contains(point) {
                    return link
                }
            }
        }
        return nil
    }
    
    //MARK: Accessibility
    override var isAccessibilityElement: Bool {
        get {
            return false
        }
        set {}
    }
    override var accessibilityFrame: CGRect {
        get {
            if let superview = superview {
                return UIAccessibility.convertToScreenCoordinates(self.bounds, in: superview)
            }else {
                return CGRect.zero
            }
        }
        set {}
    }
    
    override func accessibilityElementCount() -> Int {
        fetchAttributedRectsIfNeeded()
        return __accessibilityElements?.count ?? 0
    }
    
    override func accessibilityElement(at index: Int) -> Any? {
        if (index >= __accessibilityElements?.count ?? 0) {
            return nil
        }
        fetchAttributedRectsIfNeeded()
        return __accessibilityElements?[index]
    }
    
    override func index(ofAccessibilityElement element: Any) -> Int {
        fetchAttributedRectsIfNeeded()
        guard let item = element as? DYAccessibilityElement else {
            return -1
        }
        return __accessibilityElements?.firstIndex(of: item) ?? -1
    }
    
    override var accessibilityElements: [Any]? {
        get {
            fetchAttributedRectsIfNeeded()
            return __accessibilityElements
        }
        set{}
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
    func getCTRectFor(run:CTRun, line:CTLine,origin:CGPoint,context:CGContext) -> CGRect {
        let aP = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        let dP = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        let lP = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        defer {
            aP.deallocate()
            dP.deallocate()
            lP.deallocate()
        }
        let width = CTRunGetTypographicBounds(run, CFRange.init(location: 0, length: 0), aP, dP, lP)
        
        let q = CTRunGetStringRange(run)
        let xOffset = CTLineGetOffsetForStringIndex(line, q.location, nil)
        var boundT = CGRect.zero
        boundT.size.width = CGFloat(width)
        boundT.size.height = aP.pointee + dP.pointee
        boundT.origin.x = origin.x + CGFloat(xOffset)
        boundT.origin.y = origin.y
        boundT.origin.y -= dP.pointee
        
        return boundT
    }
    
    override func setNeedsLayout() {
        super.setNeedsLayout()
        invalidate()
    }
    
    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        invalidate()
    }
    
    
    /// Invalidate link, text, and accessibility caches
    func invalidate() {
        links = nil
        text = nil
        __accessibilityElements = nil
    }
    
    override func layoutSubviews() {
        setNeedsDisplay()
    }
    
    
    /// Generate the framesetter and framesetter frame. CALL THIS ONLY FROM dataUpdateQueue!!!
    func generateCoreTextCachesIfNeeded() {
        guard let drawingAttributed = self.__attributedText else {return}
        if self.__frameSetter == nil {
            self.__frameSetter = CTFramesetterCreateWithAttributedString(drawingAttributed)
        }
        
        if self.__frameSetterFrame == nil {
            let path = CGPath(rect: self.__frame, transform: nil)
            self.__frameSetterFrame = CTFramesetterCreateFrame(self.__frameSetter!, CFRangeMake(0, 0), path, nil)
        }
    }
    
    override func draw(_ rect: CGRect) {
        //do not call super.draw(rect), not required
        guard let ctx = UIGraphicsGetCurrentContext() else {
            fatalError()
        }
        
        dataUpdateQueue?.sync {
            //explicitly capture self otherwise we can get some weird memory issues if we are deallocated
            
            if self.__attributedText == nil {
                return
            }
            generateCoreTextCachesIfNeeded()
            //Blank the cell completely before drawing. Prevent empty grey line from being drawn
            ctx.setFillColor((self.__backgroundColor ?? UIColor.white).cgColor)
            ctx.fill(CGRect.init(x: -20, y: -20, width: self.__frame.size.width + 40, height: self.__frame.height + 40))
            
            ctx.textMatrix = CGAffineTransform.identity
            ctx.translateBy(x: 0, y: self.__frame.size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            if (self.__attributedText != nil) {
                self.drawText(attributedText: self.__attributedText!, shouldDraw: true, context: ctx, layoutRect: self.__frame, partialRect: rect, shouldStoreFrames: false)
            }
        }
    }
    
    
    /// Draw the text or don't and just calculate the height
    ///
    /// - Parameters:
    ///   - attributedText: Text to draw
    ///   - shouldDraw: If we should really draw it or just calculate heights
    ///   - context: Context to draw into or to pretend to draw in
    ///   - layoutRect: The layout size, or the total frame size
    ///   - partialRect: (REQUIRED WHEN DRAWING) the portion of text to actually render
    ///   - shouldStoreFrames: If the frames of various items (links, text, accessibilty elements) should be generated
    func drawText(attributedText: NSAttributedString, shouldDraw:Bool, context:CGContext?, layoutRect:CGRect,partialRect:CGRect? = nil, shouldStoreFrames:Bool) {
        //on iOS 13, it seems like baseline adjustments are no longer enabled by default. Is this a beta bug? Who knows.
        let iOS13BetaCursorBaselineMoveScalar:CGFloat
        if #available(iOS 13.0, *) {
            iOS13BetaCursorBaselineMoveScalar = 1.0
        }else {
            iOS13BetaCursorBaselineMoveScalar = 0
        }
        guard let frame = self.__frameSetterFrame else {return}
        if (shouldStoreFrames) {
            //Reset link, text storage arrays
            links = []
            text = []
            __accessibilityElements = []
        }
        
        //Fetch our lines, bridging to swift from CFArray
        let lines:CFArray = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(lines)
        
        //Get the line origin coordinates. These are used for calculating stock line height (w/o baseline modifications)
        var lineOrigins = [CGPoint](repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &lineOrigins);
        
        //Since we're starting from the bottom of the container we need get our bottom offset/padding (so text isn't slammed to the bottom or cut off)
        var ascent:CGFloat = 0
        var descent:CGFloat = 0
        var leading:CGFloat = 0
        if lineCount > 0 {
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, lineCount - 1), to: CTLine.self)
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
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
                //Convert the format range to something we can match to our string
                let runRange = CTRunGetStringRange(run)
                var ctRect:CGRect? = nil
                
                let attributesAtPosition:NSDictionary = unsafeBitCast(CTRunGetAttributes(run), to: NSDictionary.self) as NSDictionary
                var baselineAdjustment: CGFloat = 0.0
                if let adjust = attributesAtPosition.object(forKey: NSAttributedString.Key.baselineOffset) as? NSNumber {
                    //We have a baseline offset!
                    baselineAdjustment = CGFloat(adjust.floatValue)
                }
                
                //Move the draw head. Note that we're drawing from the un-updated drawYPositionFromOrigin. This is again thanks to CT cartesian plane where we draw from the bottom left of text too.
                let drawXPositionFromOrigin:CGFloat = lineOrigins[lineIndex].x
                context?.textPosition = CGPoint.init(x: drawXPositionFromOrigin, y: drawYPositionFromOrigin + iOS13BetaCursorBaselineMoveScalar * baselineAdjustment)
                if shouldDraw {
                    if let partialRect = partialRect {
                        //Change our UI partialRect into a CT relative rect
                        let pBottomCorrected:CGFloat = layoutRect.height - partialRect.maxX;
                        let pTopCorrected:CGFloat = layoutRect.height - partialRect.minY;
                        
                        //Check if we're in bounds OR ALMOST IN BOUNDS. This almost part is very important as we want to render text that's cut in half by the tile. We have to pay for the render twice but it's still more effecient than doing the whole thing at once.
                        let minCondition = abs(drawYPositionFromOrigin - pBottomCorrected) < 10
                        let maxCondition = abs(drawYPositionFromOrigin - pTopCorrected) < 10
                        let centerCondition = pTopCorrected > drawYPositionFromOrigin || drawYPositionFromOrigin > pBottomCorrected
                        //If we're in any of our ranges, draw!
                        if (minCondition || maxCondition || centerCondition) {
                            CTRunDraw(run, context!, CFRangeMake(0, 0))
                        }
                        
                        if let _ = attributesAtPosition.object(forKey: NSAttributedString.Key.strikethroughStyle) {
                            if ctRect == nil {
                                ctRect = getCTRectFor(run: run, line: line, origin: context!.textPosition, context: context!)
                            }
                            
                            let strikeYPosition = ctRect!.minY + ctRect!.height/2
                            context?.move(to: CGPoint.init(x: ctRect!.minX, y: strikeYPosition))
                            context?.addLine(to: CGPoint.init(x: ctRect!.maxX, y: strikeYPosition))
                            context?.strokePath()
                        }
                        
                        if let _ = attributesAtPosition.object(forKey: DYLabel.Key.FullLineUnderLine) {
                            if ctRect == nil {
                                ctRect = getCTRectFor(run: run, line: line, origin: context!.textPosition, context: context!)
                            }
                            
                            if let underlineColor = attributesAtPosition.object(forKey: DYLabel.Key.FullLineUnderLineColor) as? UIColor {
                                context?.setStrokeColor(underlineColor.cgColor)
                            }
                            
                            let strikeYPosition = ctRect!.minY
                            let scale = UIScreen.main.scale
                            
                            let width = 1 / scale
                            let offset = width / 2
                            
                            let yFinal:CGFloat = max(strikeYPosition - offset, width)
                            context?.setLineWidth(width)
                            
                            context?.beginPath()
                            
                            context?.move(to: CGPoint.init(x: 0, y: yFinal))
                            context?.addLine(to: CGPoint.init(x: layoutRect.width, y: yFinal))
                            context?.strokePath()
                        }
                    }
                }
                
                if shouldStoreFrames {
                    if ctRect == nil {
                        ctRect = getCTRectFor(run: run, line: line, origin: context!.textPosition, context: context!)
                    }
                    
                    //Extract frames *after* moving the draw head
                    let runBounds = convertCTRectToUI(rect: ctRect!)
                    var item:DYText? = nil
                    
                    if let url = attributesAtPosition.object(forKey: NSAttributedString.Key.link) {
                        var link:DYLink? = nil
                        if let url = url as? URL {
                            link = DYLink.init(bounds: runBounds, url: url, range: runRange)
                            links?.append(link!)
                        }else if let url = URL.init(string: url as? String ?? "") {
                            link = DYLink.init(bounds: runBounds, url: url, range: runRange)
                            links?.append(link!)
                        }
                        item = link
                        
                    }else {
                        item = DYText.init(bounds: runBounds, range: runRange)
                        text?.append(item!)
                    }
                    
                }
                
                //Check if this glyph run is tallest, and move it if it is
                maxLineHeight = max(currentLineHeight + baselineAdjustment, maxLineHeight)
                
            }
            //Move our position because we've completed the drawing of the line which is at most `maxLineHeight`
            drawYPositionFromOrigin += maxLineHeight
        }
        return
    }
    
    /// Calculate the height if it were drawn using `drawText`
    /// Uses the same code as drawText except it doesn't draw.
    ///
    /// - Parameters:
    ///   - attributedText: The text to calculate the height of
    ///   - width: The constraining width
    ///   - estimationHeight: The maximum (guessed) height of this text. If the text is taller than this, it will take multiple attempts to calculate (height doubles). There does not appear to be a performance drop for larger sizes, however the if this size is too large, older devices/iOS versions will yield invalid/too small heights due to CoreText weirdness.
    static func size(of attributedText:NSAttributedString, width:CGFloat, estimationHeight:CGFloat?=30000) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let textRect = CGRect.init(x: 0, y: 0, width: width, height: estimationHeight!)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        //Fetch our lines, bridging to swift from CFArray
        let lines:CFArray = CTFrameGetLines(frame) //as [AnyObject]
        let lineCount = CFArrayGetCount(lines)
        
        //Get the line origin coordinates. These are used for calculating stock line height (w/o baseline modifications)
        var lineOrigins = [CGPoint](repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &lineOrigins);
        
        //Since we're starting from the bottom of the container we need get our bottom offset/padding (so text isn't slammed to the bottom or cut off)
        var ascent:CGFloat = 0
        var descent:CGFloat = 0
        var leading:CGFloat = 0
        if lineCount > 0 {
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, lineCount - 1), to: CTLine.self)
            let lastLineRange = CTLineGetStringRange(line)
            let lastDrawnLength = lastLineRange.location + lastLineRange.length
            if lastDrawnLength != attributedText.length {
                //Estimation size is too small, try again!
                let newEstimationHeight = estimationHeight * 2
                print("Estimation size (\(estimationHeight)) too small by \(attributedText.length - lastDrawnLength) characters. Retrying with \(newEstimationHeight)!")
                return size(of: attributedText, width: width, estimationHeight: newEstimationHeight)
            }
            

            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        }
        
        //This variable holds the current draw position, relative to CT origin of the bottom left
        var drawYPositionFromOrigin:CGFloat = descent
        
        //Again, draw the lines in reverse so we don't need look ahead
        for lineIndex in (0..<lineCount).reversed()  {
            //Calculate the current line height so we can accurately move the position up later
            let lastLinePosition = lineIndex > 0 ? lineOrigins[lineIndex - 1].y: textRect.height
            let currentLineHeight = lastLinePosition - lineOrigins[lineIndex].y
            //Throughout the loop below this variable will be updated to the tallest value for the current line
            var maxLineHeight:CGFloat = currentLineHeight
            
            //Grab the current run glyph. This is used for attributed string interoperability
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
                
                //Check if this glyph run is tallest, and move it if it is
                maxLineHeight = max(currentLineHeight + baselineAdjustment, maxLineHeight)
                
                //Skip drawing since this is a height calculation
            }
            //Move our position because we've completed the drawing of the line which is at most `maxLineHeight`
            drawYPositionFromOrigin += maxLineHeight
        }
        return CGSize.init(width: width, height: drawYPositionFromOrigin)
    }
    
    public class Key {
        /// Hacky add-on to let you draw a line from the beneath  this text to from x=0 to x=max. You'll want to apply this to the line with the LOWEST baseline for proper looks
        public static let FullLineUnderLine = NSAttributedString.Key.init("DYLabel.FullLineUnderLineKey")
        public static let FullLineUnderLineColor = NSAttributedString.Key.init("DYLabel.FullLineUnderLineColorKey")
    }
}

protocol DYLinkDelegate : class {
    func didClickLink(label: DYLabel, link:DYLink);
    func didLongPressLink(label: DYLabel, link:DYLink);
}


