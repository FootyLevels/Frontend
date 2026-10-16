//
//  Utils.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import UIKit

final class Utils{
    static let shared = Utils()
    
    private init(){
        
    }
    
    @MainActor
    func getTopViewController(controller: UIViewController? = nil) -> UIViewController?{
        let controller = controller ?? Self.keyWindow?.rootViewController

        if let nav = controller as? UINavigationController{
            return getTopViewController(controller: nav.visibleViewController)
        }else if let tab = controller as? UITabBarController, let selected = tab.selectedViewController{
            return getTopViewController(controller: selected)
        }else if let presented = controller?.presentedViewController{
            return getTopViewController(controller: presented)
        }

        return controller

    }

    /// The key window of the foreground-active scene.
    ///
    /// Replaces `UIApplication.shared.keyWindow`, deprecated in iOS 13: it
    /// searched every connected scene, so in a multi-scene app it could return
    /// a window belonging to a different one — or nil. Google Sign-In presents
    /// from whatever this returns, so picking the wrong scene matters.
    @MainActor
    private static var keyWindow: UIWindow? {
        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        // Prefer the scene the person is actually looking at, but fall back to
        // any window scene so this still works before a scene activates.
        let scene = activeScenes.first { $0.activationState == .foregroundActive }
            ?? activeScenes.first

        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }
    
}
