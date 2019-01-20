//
//  DTLabel.swift
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
    unowned var superview:UIView
    var boundingRect:CGRect
    
    
    /// Due to the way that iOS translates touches performed by Voice Over, it is sometimes neccesary to include additional information so that the touch can be correctly interpreted. Link for the element is included because the touch may "miss" the link if clicked using VO because VO clicks directly in the center of the rect rather than the origin
    var link:DYLink?
    
    
    init(superview superViewIn:UIView, boundingRect bound:CGRect, container:Any) {
        superview = superViewIn
        boundingRect = bound
        
        super.init(accessibilityContainer: container)
    }
    
    
    /// Fix a bizzare bug? my issue? where the calculated frame is wrong later. YOU MUST SET BOUNDING RECT and superView
    override var accessibilityFrame: CGRect {
        get {
            return UIAccessibilityConvertFrameToScreenCoordinates(boundingRect, superview)
        }
        set{}
    }
}



/// A custom, high performance label which provides both accessibility and FAST and ACCURATE height calculation
class DYLabel: UIView {
    internal var __attributedText:NSAttributedString?
    internal var __accessibilityElements:[DYAccessibilityElement]? = nil
    var __enableFrameDebugMode = false

    
    var links:[DYLink]? = nil
    var text:[DYText]? = nil
    
    private let tapGesture = UITapGestureRecognizer()
    private let holdGesture = UILongPressGestureRecognizer()
    
    public weak var dyDelegate:DYLinkDelegate?
	
    var attributedText:NSAttributedString? {
        get {
            return __attributedText
        }
        
        set (input) {
            __attributedText = input
            self.setNeedsDisplay()
        }
    }
	
	//MARK: Tiling
	//This code enables the view to be drawn in the background, in tiles. Huge performance win especially on large bodies of text
	override class var layerClass: AnyClass {
		return CAFastFadeTileLayer.self
	}
	
	
	var tiledLayer: CAFastFadeTileLayer {
		return self.layer as! CAFastFadeTileLayer
	}
	
	//HACK: To get the background thread to stop yelling at me for doing reads when background rendering
	//THIS IS UNSAFE!!!!
	internal var __backgroundColor:UIColor? = UIColor.white
	override var backgroundColor: UIColor? {
		set (color) {
			super.backgroundColor = color
			__backgroundColor = color?.copy() as? UIColor
		}
		
		get {
			return __backgroundColor
		}
	}
	
	internal var __frame:CGRect = CGRect.zero
	override var frame: CGRect {
		set (frameIn) {
			super.frame = frameIn
			let screenHeight = UIScreen.main.bounds.height
			let height = (frameIn.height < screenHeight) ? frameIn.height : screenHeight
			tiledLayer.tileSize = CGSize.init(width: frameIn.width, height: height)
			__frame = frameIn
		}
		
		get {
			return __frame
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
        accessibilityElement.accessibilityTraits = isPlainText ? UIAccessibilityTraitStaticText : UIAccessibilityTraitLink
        accessibilityElement.link = linkItem
        
        
        return accessibilityElement
    }
    
    
    /// Calculate the frames of plain text, links, and accessibility elements (if needed)
    /// THIS IS AN EXPENSIVE OPERATION, especially if voice over is running. This method will attempt to skip itself automatically. If new data must be feteched, call `invalidate()`
    func fetchAttributedRectsIfNeeded() {
        if links == nil || ( UIAccessibilityIsVoiceOverRunning() && __accessibilityElements == nil) || self.__enableFrameDebugMode {
            UIGraphicsBeginImageContext(self.bounds.size)
            drawText(attributedText: attributedText!, shouldDraw: false, context: UIGraphicsGetCurrentContext(), layoutRect: bounds, shouldStoreFrames: true)
            UIGraphicsEndImageContext()
            
            //Accessibility element generation
            //
            /// WARNING! THIS SUBROUTINE IS VERY EXPENSIVE! It compacts links and texts into a single array, sorts it (as the links and text arrays are not exactly "sorted"), and then generates new accessibility objects)
            //
            
            var items:[DYText] = links! + text!
            items.sort { (a, b) -> Bool in
                return a.range.location < b.range.location
            }
            
            let textContent = attributedText!.string as NSString
            var lastIsText:Bool = (items.first is DYLink) == false
            var frames:[CGRect] = []
            var frameLabel = ""
            var lastLinkItem:DYLink? = items.first as? DYLink
            var nextItemIsNewParagraph:Bool = false
            for item in items {
                let currentIsText = (item is DYLink) == false
                if (lastIsText != currentIsText || nextItemIsNewParagraph) {
                    nextItemIsNewParagraph = false
                    //We've changed frames, commit accesibility element
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
        if (UIAccessibilityIsVoiceOverRunning()) {
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
            return UIAccessibilityConvertFrameToScreenCoordinates(self.bounds, self.superview!)
        }
        set {}
    }
    
    override func accessibilityElementCount() -> Int {
        fetchAttributedRectsIfNeeded()
        return __accessibilityElements!.count
    }
    
    override func accessibilityElement(at index: Int) -> Any? {
        if (index >= __accessibilityElements?.count ?? 0) {
            return nil
        }
        fetchAttributedRectsIfNeeded()
        return __accessibilityElements![index]
    }
    
    override func index(ofAccessibilityElement element: Any) -> Int {
        fetchAttributedRectsIfNeeded()
        guard let item = element as? DYAccessibilityElement else {
            return -1
        }
        return __accessibilityElements!.firstIndex(of: item) ?? -1
    }
    
    override var accessibilityElements: [Any]? {
        get {
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
    func getCTRectFor(run:CTRun,context:CGContext) -> CGRect {
        let imageBounds = CTRunGetImageBounds(run, context, CFRangeMake(0, 0))
        if #available(iOS 11.0, *) {
            //Non-bugged iOS, can assume the bounds are correct
            return imageBounds
        } else {
            //<=iOS 10 has a bug with getting the frame of a run where it gives invalid x positions
            //The CTRunGetPositionsPtr however works as expected and returns the correct position. We can take that value and substitute it
            let runPositionsPointer = CTRunGetPositionsPtr(run)
            if let runPosition = runPositionsPointer?.pointee {
                return CGRect.init(x: runPosition.x, y: imageBounds.origin.y, width: imageBounds.width, height: imageBounds.height)
            }else {
                //FAILED TO OBTAIN RUN ORIGIN? FALL BACK.
                return imageBounds
            }
        }
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
    
    override func draw(_ rect: CGRect) {
        //do not call super.draw(rect), not required
        guard let ctx = UIGraphicsGetCurrentContext() else {
            fatalError()
        }
		
		//Blank the cell completely before drawing. Prevent empty grey line from being drawn
		ctx.setFillColor((__backgroundColor ?? UIColor.white).cgColor)
		ctx.fill(CGRect.init(x: -20, y: -20, width: __frame.size.width + 40, height: __frame.height + 40))
		
		ctx.textMatrix = CGAffineTransform.identity
		ctx.translateBy(x: 0, y: __frame.size.height)
		ctx.scaleBy(x: 1.0, y: -1.0)
		if (attributedText != nil) {
			drawText(attributedText: attributedText!, shouldDraw: true, context: ctx, layoutRect: __frame, partialRect: rect, shouldStoreFrames: false)
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

		if (shouldStoreFrames) {
            //Reset link, text storage arrays
            links = []
            text = []
            __accessibilityElements = []
        }
        
        //Create our CT boiler plate
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let textRect = layoutRect
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
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
            let lastLinePosition = lineIndex > 0 ? lineOrigins[lineIndex - 1].y: textRect.height
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
                
                let attributesAtPosition:NSDictionary = unsafeBitCast(CTRunGetAttributes(run), to: NSDictionary.self) as NSDictionary
                var baselineAdjustment: CGFloat = 0.0
                if let adjust = attributesAtPosition.object(forKey: NSAttributedStringKey.baselineOffset) as? NSNumber {
                    //We have a baseline offset!
                    baselineAdjustment = CGFloat(adjust.floatValue)
                }
                
                
                //Check if this glyph run is tallest, and move it if it is
                maxLineHeight = max(currentLineHeight + baselineAdjustment, maxLineHeight)
                //Move the draw head. Note that we're drawing from the unupdated drawYPositionFromOrigin. This is again thanks to CT cartisian plane where we draw from the bottom left of text too.
                context?.textPosition = CGPoint.init(x: lineOrigins[lineIndex].x, y: drawYPositionFromOrigin)
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
					}
                }
                
                if shouldStoreFrames {
                    //Extract frames *after* moving the draw head
                    let runBounds = convertCTRectToUI(rect: getCTRectFor(run: run, context: context!))
                    var item:DYText? = nil
                    
                    if let url = attributesAtPosition.object(forKey: NSAttributedStringKey.link) {
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
    ///   - estimationHeight: Optional paramater, default 30,000px. This is the container height used to layout the text. DO NOT USE CGFLOATMAX AS IT CORE TEXT CANNOT CREATE A FRAME OF THAT SIZE.
    /// - Returns: The size required to fit the text
    static func size(of attributedText:NSAttributedString,width:CGFloat, estimationHeight:CGFloat?=30000) -> CGSize {
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
            
            //Grab the current run glyph. This is used for attributed string interop
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, lineIndex), to: CTLine.self)
            let glyphRuns = CTLineGetGlyphRuns(line)
            let glyphRunsCount = CFArrayGetCount(glyphRuns)
            for runIndex in 0..<glyphRunsCount {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(glyphRuns, runIndex), to: CTRun.self)
                
                let attributesAtPosition:NSDictionary = unsafeBitCast(CTRunGetAttributes(run), to: NSDictionary.self) as NSDictionary
                var baselineAdjustment: CGFloat = 0.0
                if let adjust = attributesAtPosition.object(forKey: NSAttributedStringKey.baselineOffset) as? NSNumber {
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
}

protocol DYLinkDelegate : class {
    func didClickLink(label: DYLabel, link:DYLink);
    func didLongPressLink(label: DYLabel, link:DYLink);
}

