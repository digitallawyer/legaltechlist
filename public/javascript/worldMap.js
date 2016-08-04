//Create world map for data vis
d3.select(window).on("resize", throttle);

var zoom = d3.zoom()
    .scaleExtent([1, 9])
    .on("zoom", function(){
      var t = validateMove(d3.event.transform);
      svg.attr("transform", t)
    });


var width = document.getElementById('map').offsetWidth;
var height = width / 2;

var topo,projection,path,svg,g;

var graticule = d3.geoGraticule();

var tooltip = d3.select("#map").append("div").attr("class", "tooltip hidden");

// upper = $('#outerG').

setup(width,height);

function setup(width,height){
  projection = d3.geoMercator()
    .translate([(width/2), (height/2)])
    .scale( width / 2 / Math.PI);

  path = d3.geoPath().projection(projection);

  svg = d3.select("#map").append("svg")
      .attr("width", width)
      .attr("height", height)
      .call(zoom)
      .on("click", click)
      .append("g")
      .attr("id","outerG");

  g = svg.append("g");

}

d3.json("/javascript/world-topo-min.json", function(error, world) {

  var countries = topojson.feature(world, world.objects.countries).features;

  topo = countries;
  draw(topo);

});

function draw(topo) {

  svg.append("path")
     .datum(graticule)
     .attr("class", "graticule")
     .attr("d", path);


  g.append("path")
   .datum({type: "LineString", coordinates: [[-180, 0], [-90, 0], [0, 0], [90, 0], [180, 0]]})
   .attr("class", "equator")
   .attr("d", path);


  var country = g.selectAll(".country").data(topo);

  country.enter().insert("path")
      .attr("class", "country")
      .attr("d", path)
      .attr("id", function(d,i) { return d.id; })
      .attr("title", function(d,i) { return d.properties.name; })
      .style("fill", function(d, i) { return d.properties.color; });

  //offsets for tooltips
  var offsetL = document.getElementById('map').offsetLeft+20;
  var offsetT = document.getElementById('map').offsetTop+10;

  //tooltips
  country
    .on("mousemove", function(d,i) {

      var mouse = d3.mouse(svg.node()).map( function(d) { return parseInt(d); } );

      tooltip.classed("hidden", false)
             .attr("style", "left:"+(mouse[0]+offsetL)+"px;top:"+(mouse[1]+offsetT)+"px")
             .html(d.properties.name);

      })
      .on("mouseout",  function(d,i) {
        tooltip.classed("hidden", true);
      });   

  var nestedData = d3.entries(data)

  var pointsRaw = nestedData.map(function(d,i){
    // var point = projection([d.value.lat,d.value.lng]);
    var point = [d.value.lat, d.value.lng]
    point.push(d.key)
    return point;
  });

  // var marker = d3.select("#map").selectAll("svg")
  //       .data(d3.entries(data))
  //       .each(transform) // update existing markers
  //     .enter().append("svg")
  //       .each(transform)
  //       .attr("class", "marker_map");

  pointsRaw.forEach(function(i){
      addpoint(i[1], i[0], i[2] );
    });

  //Add a circle.
  // marker.append("circle")
  //     .attr("r", 4.5)
  //     .attr("cx", padding)
  //     .attr("cy", padding);

  // // Add a label.
  // marker.append("text")
  //     .attr("x", padding + 7)
  //     .attr("y", padding)
  //     .attr("dy", ".31em")
  //     .text(function(d) { return d.key; });
  //       console.log(d);

  var width = parseInt(d3.select("#map").style("width"),10);
  var height = parseInt(d3.select("#map").style("height"),10);

  //  var grid = svg.append('g')
  //  .attr('class', 'grid');
   
  //  for (var x = 0; x <= width; x += clusterRange) {
  //    for (var y = 0; y <= height; y+= clusterRange) {
  //      grid.append('rect')
  //        .attr({
  //          x: x,
  //          y: y,
  //          width: clusterRange,
  //          height: clusterRange,
  //          class: "grid"
  //        });
  //    }
  //  }

  // quadtree = d3.quadtree().addAll(pointsRaw);

  // // Find the nodes within the specified rectangle.
  // function search(quadtree, x0, y0, x3, y3) {
  //   var validData = [];
  //   quadtree.visit(function(node, x1, y1, x2, y2) {
  //     var p = node.point;
  //     if (p) {
  //         p.selected = (p[0] >= x0) && (p[0] < x3) && (p[1] >= y0) && (p[1] < y3);
  //         if (p.selected) {
  //           validData.push(p);
  //        }
  //     }
  //     return x1 >= x3 || y1 >= y3 || x2 < x0 || y2 < y0;
  //   });
  //   return validData;
  // }

  // var clusterPoints = [];
  // var clusterRange = 20;

  // for (var x = 0; x <= width; x += clusterRange) {
  //   for (var y = 0; y <= height; y+= clusterRange) {
  //     var searched = search(quadtree, x, y, x + clusterRange, y + clusterRange);

  //     var centerPoint = searched.reduce(function(prev, current) {
  //       return [prev[0] + current[0], prev[1] + current[1]];
  //     }, [0, 0]);

  //     centerPoint[0] = centerPoint[0] / searched.length;
  //     centerPoint[1] = centerPoint[1] / searched.length;
  //     centerPoint.push(searched);

  //     if (centerPoint[0] && centerPoint[1]) {
  //       clusterPoints.push(centerPoint);
  //     }
  //   }
  // }

  // var pointSizeScale = d3.scaleLinear()
  //    .domain([
  //       d3.min(clusterPoints, function(d) {return d[2].length;}),
  //       d3.max(clusterPoints, function(d) {return d[2].length;})
  //    ])
  //    .rangeRound([3, 15]);

  // g.selectAll(".centerPoint")
  //   .data(clusterPoints)
  //   .enter().append("circle")
  //   .attr("class", function(d) {return "centerPoint"})
  //   .attr("cx", function(d) {return d[0];})
  //   .attr("cy", function(d) {return d[1];})
  //   .attr("fill", '#FFA500')
  //   .attr("r", 6)
  //   .on("click", function(d, i) {
  //     console.log(d);
  //   })

  //EXAMPLE: adding some capitals from external CSV file
  // d3.csv("data/country-capitals.csv", function(err, capitals) {

  //   capitals.forEach(function(i){
  //     addpoint(i.CapitalLongitude, i.CapitalLatitude, i.CapitalName );
  //   });

  // });

}

function validateMove(obj) {
  var h = height/4,
      navOffset = $(".navbar").height(); //Added additional height to account for fixed navbar
  //obj.k is the scale factor
  obj.x = Math.min(
    (width/height)  * (obj.k - 1), 
    Math.max( width * (1 - obj.k), obj.x )
  );

  obj.y = Math.min(
    h * (obj.k - 1) + h * obj.k, 
    Math.max(height  * (1 - obj.k) - h * obj.k + navOffset, obj.y)
  );

  return obj;
}

function redraw() {
  width = document.getElementById('map').offsetWidth;
  height = width / 2;
  d3.select('svg').remove();
  setup(width,height);
  draw(topo);
}

var throttleTimer;
function throttle() {
  window.clearTimeout(throttleTimer);
    throttleTimer = window.setTimeout(function() {
      redraw();
    }, 200);
}


//geo translation on mouse click in map
function click() {
  var latlon = projection.invert(d3.mouse(this));
  console.log(latlon);
}


//function to add points and text to the map (used in plotting capitals)
function addpoint(lat,lon,text) {

  var gpoint = g.append("g").attr("class", "gpoint");
  var x = projection([lat,lon])[0];
  var y = projection([lat,lon])[1];

  gpoint.append("svg:circle")
        .attr("cx", x)
        .attr("cy", y)
        .attr("class","point")
        .attr("r", 1.5);

  //conditional in case a point has no associated text
  if(text.length>0){

    gpoint.append("text")
          .attr("x", x+2)
          .attr("y", y+2)
          .attr("class","text")
          .text(text);
  }

}