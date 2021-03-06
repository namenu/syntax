[@bs.module "react-responsive-carousel"] [@react.component]
external make:
  (
    ~children: React.element,
    ~showArrows: bool,
    ~showStatus: bool,
    ~showIndicators: bool,
    ~infiniteLoop: bool,
    ~showThumbs: bool,
    ~useKeyboardArrows: bool,
    ~autoPlay: bool,
    ~stopOnHover: bool,
    ~swipeable: bool,
    ~dynamicHeight: bool,
    ~emulateTouch: bool,
    ~thumbWidth: int=?,
    ~selectedItem: int=?,
    ~interval: int=?,
    ~transitionTime: int=?,
    ~swipeScrollTolerance: int=?
  ) =>
  React.element =
  "default";
