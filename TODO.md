### Todos
- [ ] Get rid of the padding for the sortable header. It isn't const the size of the symbol is dependent on the font size?
- [ ] Handle padding when header column width is smaller than the heading button width. Currently doesn't show the separator.
- [ ] Draws over vertical scroll bar when horizontal scrolling. Need to change the clip or reserve space for the scrollbar.
- [ ] Need some defalt padding, so the first column isn;t hard against the edge of the grid.
- [ ] Fix checkbox padding or size? It's not shown the speparator.

### Issues
- [ ] Is there a better name than window size for the scroller? It's not really a window size. It's a number of extra rows to render above and below the visible rows.
        - Windows size > 1 doesn't seem to make any difference really.
- [ ] Grid header widget assumes vertical scroll bar width is 10 and that it will always be displayed. 
- [ ] Example needs to be added to Example.zig, rather than a stand-alone.
- [ ] Issue with grid headers moving while virtual scrolling. Header is set to scroll_info.vieport.y, but this is not always at the top of the viewport (due to floating point precision?)
- [ ] Gravity is applied incorrectly when virtual scrolling? i..e things will only center when scrolling stops.
        - It doesn't happen with non-virtual scrolling, so something is not expanding correctly?
        - Actually, I don't think it is gravity, it is some cells being drawn too wide while scrolling and then corrected when the scrolling stops.
        - Also note in the demo there is an "Expand" column for Description. That's not really compatible with virtual scrolling.
        - Need to investigate further.

### Future
* Some better visual indication that columns are sortable.
* Resize columns via dragging
* Filtering headers
