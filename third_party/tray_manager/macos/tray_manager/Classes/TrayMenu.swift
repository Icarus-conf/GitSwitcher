//
//  TrayMenu.swift
//  tray_manager
//
//  Created by Lijy91 on 2022/5/8.
//

import AppKit

public class TrayMenu: NSMenu, NSMenuDelegate {
    public var onMenuItemClick:((NSMenuItem) -> Void)?
    
    public override init(title: String) {
        super.init(title: title)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    public init(_ args: [String: Any]) {
        super.init(title: "")
        
        let items: [NSDictionary] = args["items"] as! [NSDictionary];
        for item in items {
            let menuItem: NSMenuItem
            
            let itemDict = item as! [String: Any]
            let id: Int = itemDict["id"] as! Int
            let type: String = itemDict["type"] as! String
            let label: String = itemDict["label"] as? String ?? ""
            let toolTip: String = itemDict["toolTip"] as? String ?? ""
            let checked: Bool? = itemDict["checked"] as? Bool
            let disabled: Bool = itemDict["disabled"] as? Bool ?? true
            // GitSwitcher patch: upstream ignores `icon` and `sublabel`.
            let icon: String? = itemDict["icon"] as? String
            let sublabel: String? = itemDict["sublabel"] as? String

            if (type == "separator") {
                menuItem = NSMenuItem.separator()
            } else {
                menuItem = NSMenuItem()
            }
            
            menuItem.tag = id
            menuItem.title = label
            menuItem.toolTip = toolTip
            menuItem.isEnabled = !disabled
            menuItem.action = !disabled ? #selector(statusItemMenuButtonClicked) : nil
            menuItem.target = self

            // GitSwitcher patch: render `icon` as the item's image. Avatars are
            // photographs, so this must NOT be a template image or macOS would
            // flatten them to a solid silhouette.
            if let iconPath = icon, let image = NSImage(contentsOfFile: iconPath) {
                menuItem.image = TrayMenu.circularImage(image, diameter: 16)
            }

            // GitSwitcher patch: render `sublabel` as a dimmer second line.
            if let sublabel = sublabel, !sublabel.isEmpty, type != "separator" {
                let title = NSMutableAttributedString(
                    string: label,
                    attributes: [.font: NSFont.menuFont(ofSize: 0)]
                )
                title.append(NSAttributedString(
                    string: "\n" + sublabel,
                    attributes: [
                        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                ))
                menuItem.attributedTitle = title
            }

            switch (type) {
            case "separator":
                break
            case "submenu":
                if let submenuDict = itemDict["submenu"] as? NSDictionary {
                    let submenu = TrayMenu(submenuDict as! [String : Any])
                    submenu.onMenuItemClick = { [weak self] (menuItem: NSMenuItem) in
                        guard let strongSelf = self else { return }
                        strongSelf.statusItemMenuButtonClicked(menuItem)
                    }
                    self.setSubmenu(submenu, for: menuItem)
                }
                break
            case "checkbox":
                if (checked == nil) {
                    menuItem.state = .mixed
                } else {
                    menuItem.state = checked! ? .on : .off
                }
                break
            default:
                break
            }
            self.addItem(menuItem)
        }
        self.delegate = self
    }
    
    // GitSwitcher patch: avatars are round everywhere else in macOS, so the
    // source image is masked to a circle rather than shown as a square.
    //
    // Drawing through NSImage(size:flipped:drawingHandler:) rather than
    // lockFocus lets AppKit rasterise at the display's scale, so the result
    // stays sharp on Retina instead of being baked at 16pt.
    static func circularImage(_ source: NSImage, diameter: CGFloat) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)

        let masked = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSBezierPath(ovalIn: rect).addClip()
            source.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }

        masked.isTemplate = false
        return masked
    }

    @objc func statusItemMenuButtonClicked(_ sender: Any?) {
        if (sender is NSMenuItem && onMenuItemClick != nil) {
            let menuItem = sender as! NSMenuItem
            self.onMenuItemClick!(menuItem)
        }
    }
    
    // NSMenuDelegate
    
    public func menuDidClose(_ menu: NSMenu) {
        
    }
}
