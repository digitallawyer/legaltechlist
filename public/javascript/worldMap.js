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


  //EXAMPLE: adding some capitals from external CSV file
  // d3.csv("data/country-capitals.csv", function(err, capitals) {

  //   capitals.forEach(function(i){
  //     addpoint(i.CapitalLongitude, i.CapitalLatitude, i.CapitalName );
  //   });

  // });

}

function validateMove(obj) {
  var h = height/4;
  //obj.x = x pos, obj.y = y pos, obj.k = zoom value
  obj.x = Math.min(
    (width/height)  * (obj.k - 1), 
    Math.max( width * (1 - obj.k), obj.x )
  );

  obj.y = Math.min(
    h * (obj.k - 1) + h * obj.k, 
    Math.max(height  * (1 - obj.k) - h * obj.k, obj.y)
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