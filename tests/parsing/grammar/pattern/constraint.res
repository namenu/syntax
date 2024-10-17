switch thing {
| Some((node: node)) => ()
| Some(node: Feature.node) => ()
| list{(child: node), ...rest} => ()
| list{child: node, ...rest} => ()
| (Some(_), Some((menuItem: Menu.item))) => ()
| (Some(_), Some(menuItem: Menu.item)) => ()
| SettingChanged(({fullName, value, _}: Nova.Setting.t)) => ()
| SettingChanged({fullName, value, _}: Nova.Setting.t) => ()
}
