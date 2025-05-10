### Todos

### Issues
- [ ] Virtual scrolling is sometimes smooth and sometimes flickers by 1 row. 
    - Likely some floating point rounding issue.
    - Is less apparent when vsync = false
    - Possibly resolved by not forcing the grid to scroll on full rows.
- [ ] Virtual scrolling with large row heights doesn't work well because of the way it snaps to the next visible row.
- [ ] scrolling header and body simultaneously is not a smooth as I'd like.
- [ ] Columns flash when sorting. Only the separator is shown and appears that label is not rendered or rendered with no label.
- [ ] If headers are bigger than cols, then doesn't show grid data until next refresh.
- [ ] Is there a better name than window size for the scroller? It's not really a window size. It's a number of extra rows to render above and below the visible rows.
- [ ] Checkbox doesn't expand to the full height of the header.
- [ ] Remove the need to pass the same (or sometimes different) styling to the header vs the body.
- [ ] Make column headers respect column width "ownership" so that .expand can be used on the body columns. 
- [ ] Grid header widget assumes vertical scroll bar width is 10 and that it will always be displayed. 
- [ ] Example needs to be added to Example.zig, rather than a stand-alone.

### Future
* Some better visual indication that columns are sortable.
* Make the GridWidget do the layout calculations, rather than relying on hbox / vbox layouts. 
    - Then each column have a style of fixed, expanding, size_to_content etc.
    - The grid Widget can then take into account the available space and size each column accordingy.
    - Potentially it would allows layout out data by row rather than just by col.
    - Would likely fix the issue of the header and body not being 100% in sync while scrolling.
* Resize columns via dragging
* Filtering headers


