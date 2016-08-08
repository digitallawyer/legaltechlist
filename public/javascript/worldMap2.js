//var data is defined in map html (passed from ruby)

var map = new google.maps.Map(d3.select("#map").node(), {
  zoom: 2,
  minZoom:2,
  maxZoom:13,
  center: new google.maps.LatLng(0,0),
  // center: new google.maps.LatLng(37.76487, -122.41948),
  mapTypeId: google.maps.MapTypeId.TERRAIN 
});

var overlay = new google.maps.OverlayView();
var width = parseInt(d3.select("#map").style("width"),10);
var height = parseInt(d3.select("#map").style("height"),10);
// Add the container when the overlay is added to the map.
overlay.onAdd = function() {
  var layer = d3.select(this.getPanes().overlayLayer).append("div")
      .attr("class", "companies_map");

  // Draw each marker as a separate SVG element.
  // We could use a single SVG, but what size would it have?
  overlay.draw = function() {
    var projection = this.getProjection(),
        padding = 10;

    var nestedData = d3.entries(data)
    var pointsRaw = nestedData.map(function(d,i){
      // console.log(projection)
      var mapP = new google.maps.LatLng(d.value.lat,d.value.lng);
      mapP = projection.fromLatLngToDivPixel(mapP)
      var point = [mapP.x, mapP.y]
      point.push(d.key)
      return point;
    });

    var width = parseInt(d3.select("#map").style("width"),10);
    var height = parseInt(d3.select("#map").style("height"),10);

    quadtree = d3.quadtree().addAll(pointsRaw);

    var cPoints = quadtreeTraversal(quadtree);
    console.log(cPoints)
    // console.log(clusterPoints.length)
//array[2].length == 1 --> single company from quadtree cpoints
    var pointSizeScale = d3.scaleLinear()
       .domain([
          d3.min(cPoints, function(d) {return d[2].length;}),
          d3.max(cPoints, function(d) {return d[2].length;})
       ])
       .rangeRound([3, 15]);
    console.log(d3.entries(data))

    var marker = layer.selectAll("svg")
          .data(cPoints)
          .each(transform) // update existing markers
        .enter().append("svg")
          .each(transform)
          .attr("class", "marker_map");

      //Add a circle.
      marker.append("circle")
          .attr("r", 6.5)
          .attr("cx", padding)
          .attr("cy", padding);

      // Add a label.
      // marker.append("text")
      //     .attr("x", padding)
      //     .attr("y", padding)
      //     // .attr("dy", ".31em")
      //     .attr("text-anchor","middle")
      //     .attr("alignment-baseline","middle")
      //     .text(function(d) { return d[2].length; });


      function transform(d) {
        // d = new google.maps.LatLng(d.value.lat, d.value.lng);
        // d = projection.fromLatLngToDivPixel(d);

        return d3.select(this)
          .style("left", (d[0] - padding) + "px")
          .style("top", (d[1] - padding) + "px");
    }
  };
};

// Find the nodes within the specified rectangle.
function search(quadtree, x0, y0, x3, y3) {
  validData = [];
  quadtree.visit(function(node, x1, y1, x2, y2) {
    if (!node.length){
      var p = [node.data[0], node.data[1], node.data[2]];
    // if (!node.length) do console.log(node.data); while (node = node.next)
      if (p) {
          p.selected = (p[0] >= x0) && (p[0] < x3) && (p[1] >= y0) && (p[1] < y3);
          if (p.selected) {
            validData.push(p);
         }
      }
    }
    return x1 >= x3 || y1 >= y3 || x2 < x0 || y2 < y0;
  });
  return validData;
}

function quadtreeTraversal(quadtree){
  var clusterPoints = [];
  var clusterRange = 60;

  for (var x = 0; x <= width; x += clusterRange) {
    for (var y = 0; y <= height; y+= clusterRange) {
      var searched = search(quadtree, x, y, x + clusterRange, y + clusterRange);
      // if(searched.length != 0){
        var centerPoint = searched.reduce(function(prev, current) {
          return [prev[0] + current[0], prev[1] + current[1]];
        }, [0, 0]);

        centerPoint[0] = centerPoint[0] / searched.length;
        centerPoint[1] = centerPoint[1] / searched.length;
        centerPoint.push(searched);
        if (centerPoint[0] && centerPoint[1]) {
          clusterPoints.push(centerPoint);
        }
      // }
    }
  }

  return clusterPoints;
}

var lastValidCenter = map.getCenter()
google.maps.event.addListener(map, 'drag', function(){

  var proj =map.getProjection();
  var bounds = map.getBounds();
  var sLat =map.getBounds().getSouthWest().lat();
  var nLat = map.getBounds().getNorthEast().lat();

  if (sLat < -85 || nLat > 85) {
    map.setCenter(lastValidCenter)
   }else {
      lastValidCenter = map.getCenter();
   }
});
// Bind our overlay to the map…
overlay.setMap(map);