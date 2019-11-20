package Visualise::RenderTopologydot;
use Visualise::Visualise;
use Visualise::Container;
use Visualise::Render;
use Math::Gradient qw(multi_array_gradient);
our @ISA = qw(Visualise::Render Visualise::Visualise);
use strict;

my %all_containers;
my %title_map;
my $cluster_id = 0;
my $outputFormat;
my @gradient;

sub initialise() {
	my ($self) = @_;
	$self->{_ModuleName} = "RenderTopologydot";
	$self->SUPER::initialise();

	my @spots = ([ 255, 255, 255 ], [ 0, 255, 0 ], [ 255, 255, 0 ], [ 255, 165, 0 ], [ 255, 0, 0 ], [100, 50, 50 ] );
	@gradient = multi_array_gradient(101, @spots);
}

sub setOutput() {
	my ($self, $directory) = @_;

	$self->setOutputDirectory($directory);
}

sub loadToColour() {
	my ($self, $load) = @_;

	my $color = sprintf("#%02X%02X%02X", int($gradient[int $load][0]), int($gradient[int $load][1]), int($gradient[int $load][2]));
	return $color;
}

sub cpuLabel {
	my ($label, $container) = @_;

	my @elements = split(/ /, $label);
	return sprintf("cpu %03d\\n%4.2f%%", $elements[1], $container->{_Value});
}

my $clusterID = 0;
my %renderSublevel;
my $multiLLC = 0;
my @firstCores;
my $splitLLC = 4;
my $splitCores = 4;

sub renderLevel {
	my ($self, $level, $renderSubgraph, $container, $layoutNodesRef, $layoutNodePrefix) = @_;
	my $indent = sprintf("%" . ($level * 2) . "s", " ");
	my $dot;
	my $place;

	# Final level
	my $label = $container->{_Title};
	if (ref($container->{_SubContainers}) ne "ARRAY") {
		$label = cpuLabel($label, $container);

		my $colour = "#ffffff";
		my $load = $container->{_Value};
		if ($load ne "" && $load != 0) {
			$colour = $self->loadToColour($load);
		}

		return "${indent}\"$label\" [ shape=square,style=filled,fillcolor=\"$colour\" ];\n";
	}

	if ($renderSubgraph) {
		$dot .= "${indent}subgraph cluster_$clusterID  {\n";
		$dot .= "${indent}  label = \"$container->{_Title}$place\"\n";
		$dot .= "\n";
	}

	$renderSublevel{$level} = 1;
	if (scalar(@{$container->{_SubContainers}}) == 1) {
		$renderSublevel{$level} = 0;
	}
	if ($level == 2 && $renderSublevel{$level}) {
		$multiLLC = 1;
	}
	my $containerIndex = 0;
	my @layoutNodes;

	# Record first CPU of every core within an llc
	if ($level == 3) {
		@firstCores = ();
	}
	if ($level == 4) {
		my $firstContainer = @{$container->{_SubContainers}}[0];
		my $firstLabel = cpuLabel($firstContainer->{_Title}, $firstContainer);
		push @firstCores, $firstLabel;
	}

	foreach my $subContainer (reverse(@{$container->{_SubContainers}})) {
		$clusterID++;
		$containerIndex++;
		$dot .= renderLevel($self, $level + 1, $renderSublevel{$level}, $subContainer, \@layoutNodes, "${layoutNodePrefix}_");

		# Special case layout of LLC when there are multiple ones per socket
		if ($level == 3 && $multiLLC) {
			if ($containerIndex % $level == 0) {
				push @{$layoutNodesRef}, "lNode$layoutNodePrefix${containerIndex}_$clusterID";
				$dot .= "${indent} lNode$layoutNodePrefix${containerIndex}_$clusterID [ label = \"\", style=invis, shape=point]\n";
			}
		}
	}

	if ($multiLLC) {
		for (my $i = 0; $i < scalar(@layoutNodes) - 1; $i++) {
			if ((scalar(@layoutNodes) - $i < $splitLLC) || (($i + 1) % 5 != 0)) {
				$dot .= "${indent}$layoutNodes[$i] -> $layoutNodes[$i+1]\n";
			}
		}
	}
	if ($renderSubgraph) {
		$dot .= "${indent}}\n";
	}

	return $dot;
}

sub renderOne() {
	my ($self, $model) = @_;
	my $container = $model->getModel();

	my $dot = "digraph {\n";
	$dot .= "  graph [ compound=true ]\n";
	
	$dot .= "  label = \"" . $container->getContainerTitle() . "\"\n";

	foreach my $nodeContainer (@{$container->{_SubContainers}}) {
		$dot .= $self->renderLevel(1, 1, $nodeContainer);
		if (scalar(@firstCores) > $splitCores * 2) {
			for (my $i = scalar(@firstCores) - 1; $i > 0; $i--) {
				if ($i % $splitCores != 0) {
					$dot .= "  \"@firstCores[$i]\" -> \"@firstCores[$i-1]\" [ style=invis]\n";
				}
			}
		}
	}

	$dot .= "}\n";

	my $frame = $self->getNrFrames();
	open (my $output, ">$self->{_OutputDirectory}/scratch/frame-$frame.dot") || die("Failed to open output dot file");
	print $output $dot;
	close($output);

	system("dot -T$self->{_OutputFormat} $self->{_OutputDirectory}/scratch/frame-$frame.dot -o $self->{_OutputDirectory}/frames/frame-$frame.$self->{_OutputFormat}");
	$frame++;
	$self->SUPER::renderOne();
}

sub clearValues() {
	foreach my $container (%all_containers) {
		$container->{_Value} = undef;
	}
}

1;