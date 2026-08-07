defmodule BB.TUI.Viz.RobotScene do
  @moduledoc """
  Builds an `ExRatatui.ThreeD.Scene` from a `BB.Robot` topology and live joint
  configurations.

  Forward kinematics is delegated to `BB.Robot.Kinematics.all_link_transforms/2`,
  so every joint type — planar and floating included — poses correctly; this
  module only converts base-frame link transforms into the engine's scene. The
  robot is Z-up (URDF); the scene is wrapped in a -90°-about-X root frame so it
  renders in the engine's Y-up conventions. Pure: `(robot_struct, configurations)`
  in, `Scene` out.
  """

  require Logger

  alias BB.Math.{Quaternion, Vec3}
  alias BB.Math.Transform, as: BBTransform
  alias BB.Robot.Kinematics
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Node, Object, Scene, Transform}

  @default_color {160, 160, 170}
  @half_pi :math.pi() / 2.0

  @doc """
  Builds the 3D scene for `robot` at the given joint `configurations`.

  Options: `:lights` and `:background` override the defaults.
  """
  @spec build(struct(), %{atom() => number() | struct()}, keyword()) :: Scene.t()
  def build(robot, configurations, opts \\ []) do
    transforms = Kinematics.all_link_transforms(robot, configurations)

    link_nodes =
      Enum.flat_map(robot.topology.link_order, fn link_name ->
        link = Map.fetch!(robot.links, link_name)

        case visual_object(link.visual) do
          nil ->
            []

          visual ->
            [%Node{transform: world_transform(Map.fetch!(transforms, link_name)), visual: visual}]
        end
      end)

    root_node = %Node{
      transform: %Transform{rotation: {:axis_angle, {1.0, 0.0, 0.0}, -@half_pi}},
      children: link_nodes
    }

    Node.to_scene(root_node,
      lights: Keyword.get(opts, :lights, default_lights()),
      background: Keyword.get(opts, :background, {16, 16, 22})
    )
  end

  @doc "A sensible default orbit camera for the arm."
  @spec default_camera() :: Camera.t()
  def default_camera do
    %Camera{position: {0.4, 0.35, 0.4}, target: {0.0, 0.12, 0.0}}
  end

  defp default_lights do
    [
      Light.ambient({110, 110, 120}, 1.0),
      Light.directional({1.0, 1.0, 1.0}, {255, 255, 255}, intensity: 1.0),
      Light.directional({-1.0, 1.0, -1.0}, {255, 255, 255}, intensity: 0.5)
    ]
  end

  # bb base-frame transform (4x4) -> engine node transform (translation + quaternion).
  defp world_transform(%BBTransform{} = transform) do
    translation = BBTransform.get_translation(transform)
    q = Quaternion.from_rotation_matrix(BBTransform.get_rotation(transform))

    %Transform{
      position: {Vec3.x(translation), Vec3.y(translation), Vec3.z(translation)},
      rotation: {:quat, {Quaternion.x(q), Quaternion.y(q), Quaternion.z(q), Quaternion.w(q)}}
    }
  end

  # URDF rpy = Rz(yaw)·Ry(pitch)·Rx(roll).
  defp rpy_transform({roll, pitch, yaw}) do
    rx = %Transform{rotation: {:axis_angle, {1.0, 0.0, 0.0}, roll}}
    ry = %Transform{rotation: {:axis_angle, {0.0, 1.0, 0.0}, pitch}}
    rz = %Transform{rotation: {:axis_angle, {0.0, 0.0, 1.0}, yaw}}
    Transform.compose(Transform.compose(rz, ry), rx)
  end

  defp visual_object(nil), do: nil

  defp visual_object(%{geometry: geometry} = visual) do
    {mesh, geom_transform} = geometry_mesh(geometry)
    origin = visual_origin_transform(Map.get(visual, :origin))

    %Object{
      mesh: mesh,
      material: %Material{color: color(Map.get(visual, :material))},
      transform: Transform.compose(origin, geom_transform)
    }
  end

  # Link visual origin is a 2-tuple {position, orientation} (or nil).
  defp visual_origin_transform(nil), do: %Transform{}

  defp visual_origin_transform({pos, rpy}) do
    Transform.compose(%Transform{position: pos}, rpy_transform(rpy))
  end

  # geometry -> {mesh, transform applying scale (+ axis fix for cylinder)}
  defp geometry_mesh({:box, %{x: x, y: y, z: z}}) do
    {Mesh.cube(), %Transform{scale: {x, y, z}}}
  end

  defp geometry_mesh({:sphere, %{radius: r}}) do
    {Mesh.sphere(), %Transform{scale: {2.0 * r, 2.0 * r, 2.0 * r}}}
  end

  defp geometry_mesh({:cylinder, %{radius: r, height: h}}) do
    # Primitive axis +Y; URDF axis +Z. Scale in primitive frame then +90° about X.
    {Mesh.cylinder(),
     %Transform{rotation: {:axis_angle, {1.0, 0.0, 0.0}, @half_pi}, scale: {2.0 * r, h, 2.0 * r}}}
  end

  defp geometry_mesh(other) do
    Logger.warning("RobotScene: unsupported geometry #{inspect(other)}; using a unit cube")
    {Mesh.cube(), %Transform{}}
  end

  defp color(%{color: %{red: r, green: g, blue: b}}), do: {ch(r), ch(g), ch(b)}
  defp color(_), do: @default_color

  defp ch(v), do: v |> Kernel.*(255) |> round() |> max(0) |> min(255)
end
