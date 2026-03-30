# SPDX-License-Identifier: Apache-2.0

defmodule Dev.TestRobot do
  @moduledoc """
  A simulated WidowX-200 style robot arm for development.

  Based on the WidowX-200 5-DOF robot arm kinematic structure but without
  any hardware controllers — purely for TUI development and testing.
  """
  use BB
  import BB.Unit

  settings do
    name(:test_robot)
  end

  topology do
    link :base_link do
      visual do
        origin do
          z(~u(0.036 meter))
        end

        cylinder do
          radius(~u(0.04 meter))
          height(~u(0.072 meter))
        end

        material do
          name(:base_grey)

          color do
            red(0.3)
            green(0.3)
            blue(0.3)
            alpha(1.0)
          end
        end
      end

      joint :waist do
        type(:revolute)

        origin do
          z(~u(0.072 meter))
        end

        limit do
          lower(~u(-180 degree))
          upper(~u(180 degree))
          effort(~u(8 newton_meter))
          velocity(~u(180 degree_per_second))
        end

        link :shoulder_link do
          visual do
            origin do
              z(~u(0.019 meter))
            end

            box do
              x(~u(0.05 meter))
              y(~u(0.045 meter))
              z(~u(0.038 meter))
            end

            material do
              name(:shoulder_black)

              color do
                red(0.1)
                green(0.1)
                blue(0.1)
                alpha(1.0)
              end
            end
          end

          joint :shoulder do
            type(:revolute)

            origin do
              z(~u(0.03865 meter))
            end

            axis do
              roll(~u(90 degree))
            end

            limit do
              lower(~u(-108 degree))
              upper(~u(113 degree))
              effort(~u(18 newton_meter))
              velocity(~u(180 degree_per_second))
            end

            link :upper_arm_link do
              visual do
                origin do
                  x(~u(0.025 meter))
                  z(~u(0.1 meter))
                end

                box do
                  x(~u(0.035 meter))
                  y(~u(0.035 meter))
                  z(~u(0.2 meter))
                end

                material do
                  name(:upper_arm_silver)

                  color do
                    red(0.7)
                    green(0.7)
                    blue(0.75)
                    alpha(1.0)
                  end
                end
              end

              joint :elbow do
                type(:revolute)

                origin do
                  x(~u(0.05 meter))
                  z(~u(0.2 meter))
                end

                axis do
                  roll(~u(90 degree))
                end

                limit do
                  lower(~u(-108 degree))
                  upper(~u(93 degree))
                  effort(~u(13 newton_meter))
                  velocity(~u(180 degree_per_second))
                end

                link :forearm_link do
                  visual do
                    origin do
                      x(~u(0.1 meter))
                    end

                    box do
                      x(~u(0.2 meter))
                      y(~u(0.035 meter))
                      z(~u(0.035 meter))
                    end

                    material do
                      name(:forearm_silver)

                      color do
                        red(0.7)
                        green(0.7)
                        blue(0.75)
                        alpha(1.0)
                      end
                    end
                  end

                  joint :wrist_angle do
                    type(:revolute)

                    origin do
                      x(~u(0.2 meter))
                    end

                    axis do
                      roll(~u(90 degree))
                    end

                    limit do
                      lower(~u(-100 degree))
                      upper(~u(123 degree))
                      effort(~u(5 newton_meter))
                      velocity(~u(180 degree_per_second))
                    end

                    link :wrist_link do
                      visual do
                        origin do
                          x(~u(0.0325 meter))
                        end

                        box do
                          x(~u(0.065 meter))
                          y(~u(0.035 meter))
                          z(~u(0.035 meter))
                        end

                        material do
                          name(:wrist_black)

                          color do
                            red(0.1)
                            green(0.1)
                            blue(0.1)
                            alpha(1.0)
                          end
                        end
                      end

                      joint :wrist_rotate do
                        type(:revolute)

                        origin do
                          x(~u(0.065 meter))
                        end

                        axis do
                          pitch(~u(90 degree))
                        end

                        limit do
                          lower(~u(-180 degree))
                          upper(~u(180 degree))
                          effort(~u(1 newton_meter))
                          velocity(~u(180 degree_per_second))
                        end

                        link :gripper_link do
                          visual do
                            origin do
                              x(~u(0.02 meter))
                            end

                            box do
                              x(~u(0.04 meter))
                              y(~u(0.05 meter))
                              z(~u(0.025 meter))
                            end

                            material do
                              name(:gripper_dark)

                              color do
                                red(0.2)
                                green(0.2)
                                blue(0.2)
                                alpha(1.0)
                              end
                            end
                          end

                          joint :gripper do
                            type(:prismatic)

                            origin do
                              x(~u(0.0415 meter))
                            end

                            axis do
                              pitch(~u(90 degree))
                            end

                            limit do
                              lower(~u(0.015 meter))
                              upper(~u(0.037 meter))
                              effort(~u(5 newton))
                              velocity(~u(0.05 meter_per_second))
                            end

                            link :left_finger_link do
                              visual do
                                origin do
                                  x(~u(0.02 meter))
                                  y(~u(0.015 meter))
                                end

                                box do
                                  x(~u(0.04 meter))
                                  y(~u(0.01 meter))
                                  z(~u(0.02 meter))
                                end

                                material do
                                  name(:finger_grey)

                                  color do
                                    red(0.4)
                                    green(0.4)
                                    blue(0.4)
                                    alpha(1.0)
                                  end
                                end
                              end

                              joint :ee_fixed do
                                type(:fixed)

                                origin do
                                  x(~u(0.0385 meter))
                                end

                                link(:ee_link)
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
