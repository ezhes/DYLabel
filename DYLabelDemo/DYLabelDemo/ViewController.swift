//
//  ViewController.swift
//  DYLabelDemo
//
//  Created by Allison Husain on 10/14/18.
//  Copyright © 2018 Allison Husain. All rights reserved.
//

import UIKit

class ViewController: UIViewController, DYLinkDelegate {
//                                   ^^^^^^^^^^^^^^^^^^ note that we are implmenting DYLinkDelegate, this lets us recieve link touches/holds
    
    //MARK: DYLinkDelegate methods
    
    func didClickLink(label: DYLabel, link: DYLink) {
        let alert = UIAlertController.init(title: "Link click", message: "Link \(link.url)", preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: nil))
        self.show(alert, sender: nil)
    }
    
    func didLongPressLink(label: DYLabel, link: DYLink) {
        let alert = UIAlertController.init(title: "Link long press", message: "Link \(link.url)", preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: nil))
        self.show(alert, sender: nil)
    }
    
    //MARK: Creating the label
    var label:DYLabel!
    override func viewDidLoad() {
        super.viewDidLoad()
        //Step 0: Get some attributed text. I'm using my library (named HTMLFastParse, also a drop in code library) to create it
        let formatter = FormatToAttributedString.init()
        let attributedString = formatter.attributedString(forHTML: "Link test <a href=\"https://google.com/first\">first</a> and another <a href=\"https://google.com/second\">link</a>.\n\nDynamic baseline/super <sup>script <sup>also <sup>works <sup>correctly</sup></sup></sup>")!
//        let attributedString = formatter.attributedString(forHTML: "Hi!")!
        view.backgroundColor = .red

        //Step 2: Create the label
        label = DYLabel.init(attributedText: attributedString, backgroundColor: UIColor.white, frame: CGRect.zero)
        
        //Step 3: Size the label correctly, setup the frame
        //Calculate the exact height of the text given a restricting width
        let requiredSize = DYLabel.size(of: attributedString, width: self.view.frame.width, estimationHeight: 3000)
        
        //Step 4: Final configuration
        label.frame = CGRect.init(x: 0, y: 100, width: requiredSize.width, height: requiredSize.height)
        //Setup our delegate so we recieve clicks and holds
        label.dyDelegate = self
        
        //Step 5: Add it to the view
        self.view.addSubview(label)
        
        //and we're done!
        //Uncoment this line to show the debugging rects (useful for accessibility work when using the simulator)
        showRects(label: label)
    }

    private func showRects(label:DYLabel) {
        label.enableFrameDebugMode = true
        let _ = label.accessibilityElementCount()
        for t in (label.dyAccessibilityElements ?? []).reversed() {
            let f = label.convert(t.boundingRect, to: self.view)
            let v = UIView.init(frame: f)
            v.isUserInteractionEnabled = false
            v.backgroundColor = getRandomColor(alpha: 0.5)
            self.view.addSubview(v)
        }
    }
    
    private func getRandomColor(alpha:CGFloat) -> UIColor{
        let randomRed:CGFloat = CGFloat(drand48())
        let randomGreen:CGFloat = CGFloat(drand48())
        let randomBlue:CGFloat = CGFloat(drand48())
        
        return UIColor(red: randomRed, green: randomGreen, blue: randomBlue, alpha: alpha)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
//        for i in 0..<128 {
//            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) / 128, execute: {
//                self.label.setNeedsDisplay()
//                self.label.setNeedsLayout()
//            })
//        }
    }
    
}

