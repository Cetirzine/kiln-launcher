import SwiftUI
import AppKit
import LauncherCore

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(T("关于", "About"))
            PageScroll {
                VStack(spacing: 14) {
                    Card {
                        HStack(spacing: 14) {
                            Logo()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(AppInfo.shortName).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                                Text(T("为 Mac 与 Apple 芯片打造的 Minecraft: Java Edition 启动器",
                                       "A Minecraft: Java Edition launcher built for Mac and Apple Silicon"))
                                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                                Text("\(AppInfo.version) · macOS \(RuleContext.osVersion) · \(Arch.native)")
                                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                                Text(T("作者：\(AppInfo.author)", "By \(AppInfo.author)"))
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                                    .padding(.top, 2)
                            }
                            Spacer()
                            LinkButton(title: "GitHub", url: Links.repository)
                                // 与下方列表项的按钮右侧对齐
                                .padding(.trailing, 10)
                        }
                    }
                    Card(T("致谢", "Thanks")) {
                        ListItem(systemIcon: "person.fill", title: T("龙腾猫跃", "LTCat (龙腾猫跃)"),
                                 info: T("Plain Craft Launcher 2（PCL2）的作者。本启动器的部分思路受 PCL2 启发。",
                                         "Author of Plain Craft Launcher 2 (PCL2). Some ideas in this launcher were inspired by PCL2.")) {
                            LinkButton(title: T("主页", "Homepage"), url: Links.pcl2Author)
                        }
                        ListItem(systemIcon: "cube.fill", title: "Plain Craft Launcher 2",
                                 info: T("一款出色的 Minecraft 启动器。", "An excellent Minecraft launcher.")) {
                            LinkButton(title: "GitHub", url: Links.pcl2)
                        }
                        ListItem(systemIcon: "shippingbox.fill", title: "HMCL",
                                 info: T("Forge / NeoForge 安装流程与崩溃分析的实现思路参考了 HMCL。", "The Forge / NeoForge install flow and crash analysis follow approaches used by HMCL.")) {
                            LinkButton(title: "GitHub", url: Links.hmcl)
                        }
                        ListItem(systemIcon: "bolt.fill", title: "MetalUniversal",
                                 info: T("为 Apple 芯片提供实验性的 Metal 渲染后端。", "An experimental Metal rendering backend for Apple Silicon.")) {
                            LinkButton(title: "GitHub", url: Links.metalUniversal)
                        }
                        ListItem(systemIcon: "server.rack", title: "BMCLAPI (bangbang93)",
                                 info: T("提供 Minecraft 镜像下载源。", "Provides the Minecraft download mirror.")) {
                            LinkButton(title: T("网站", "Website"), url: Links.bmclapi)
                        }
                        ListItem(systemIcon: "magnifyingglass", title: "Modrinth",
                                 info: T("Mod、资源包与光影的搜索与下载。", "Search and downloads for mods, resource packs and shaders."))
                        ListItem(systemIcon: "flame", title: "CurseForge 与 MCIM（z0z0r4）",
                                 info: T("CurseForge 上的 Mod 与资源；MCIM 提供了无需密钥的社区镜像。", "Mods and resources on CurseForge; MCIM provides a community mirror that needs no API key.")) {
                            LinkButton(title: "MCIM", url: "https://mod.mcimirror.top")
                        }
                        ListItem(systemIcon: "person.badge.key.fill", title: "authlib-injector（yushijinhun）",
                                 info: T("外置登录与离线皮肤；在需要时下载，不随应用分发。", "Third-party login and offline skins; downloaded when needed, not bundled.")) {
                            LinkButton(title: "GitHub", url: "https://github.com/yushijinhun/authlib-injector")
                        }
                        Text(T("界面布局参考了 Lunar Client。", "The layout is inspired by Lunar Client."))
                            .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        Text(T("\(AppInfo.shortName) 是独立开发的项目，与 PCL 及其作者没有关联，也未获得其认可。请勿向 PCL 反馈本软件的问题。",
                               "\(AppInfo.shortName) is an independent project. It is not affiliated with or endorsed by PCL or its author. Please don't report issues with this software to PCL."))
                            .font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                    Card(T("法律信息", "Legal")) {
                        Text(T("Minecraft 是 Mojang Studios 的商标。本软件不是 Mojang 或 Microsoft 的官方产品。请购买正版游戏。",
                               "Minecraft is a trademark of Mojang Studios. This software is not an official Mojang or Microsoft product. Please buy the game."))
                            .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        Button(T("购买 Minecraft", "Buy Minecraft")) { Links.open(Links.buyMinecraft) }.buttonStyle(.kiln)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}

/// 外部链接按钮：统一宽度，一列按钮左右对齐
private struct LinkButton: View {
    let title: String
    let url: String
    var body: some View {
        Button { Links.open(url) } label: {
            Text(title).lineLimit(1).frame(width: 76)
        }
        .buttonStyle(.kiln)
    }
}
