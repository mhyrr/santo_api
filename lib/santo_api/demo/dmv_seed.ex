defmodule SantoApi.Demo.DmvSeed do
  @moduledoc """
  A small, re-runnable DMV garage for product and visual review.

  Event coordinates come from public WDCR and Katie's Cars & Coffee listings.
  Members, cars, participation narratives, details, reactions, and replies are
  fictional. They exist to exercise Vin Santo's real owner and event write
  paths without presenting public entry lists or social posts as app members.

  This is deliberately separate from `priv/repo/seeds.exs`. The repository
  seed establishes application state; this optional dataset establishes a
  believable review environment.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts
  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.Events
  alias SantoApi.Events.{EventAttachment, EventOccurrence, EventParticipation}
  alias SantoApi.Origination
  alias SantoApi.Owners
  alias SantoApi.Owners.Stories
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo
  alias SantoApi.Social

  @wdcr_ax_source "https://www.motorsportreg.com/events/wdcr-2026-ax-championship-event-2-regency-furniture-stadium-scca-802440"
  @wdcr_hpde_source "https://www.motorsportreg.com/events/wdcr-hpde-tt-4-summit-point-apr-24-26-circuit-scca-washington-dc-071517"
  @katies_source "https://www.facebook.com/groups/710572889036708/"
  @katies_listing "https://carscene.net/events/c17650f7-4cdf-408b-8b57-6edc67b4734c"

  @cars [
    %{
      key: :cayman,
      email: "apexledger@demo.vinsanto.test",
      handle: "apexledger",
      sentence: "DMV demo · 2007 Porsche Cayman S in Arctic Silver, 41,660 miles",
      claims: [
        %{predicate: "identity.model_year", value: 2007},
        %{predicate: "identity.marque", value: "porsche"},
        %{
          predicate: "identity.model",
          value: %{"code" => "cayman_s", "label" => "Cayman S"}
        },
        %{predicate: "identity.market", value: "us"},
        %{predicate: "state.exterior", value: %{"summary" => "Arctic Silver Metallic"}},
        %{predicate: "observation.mileage", value: 41_660}
      ],
      story: %{
        tagline: "Bought for the roads, slowly made my own.",
        body:
          "I wanted a simple, analog car I would not be afraid to use. It still carries the marks from long trips and autocross weekends. The aim is better feel and durability without sanding away what Porsche got right."
      },
      entries: [
        %{
          date: ~D[2026-03-14],
          claims: [
            %{
              predicate: "event.modification",
              value: %{
                "summary" => "Road-and-autocross suspension refresh",
                "area" => "chassis",
                "detail" => "Kept the street ride compliant and added front adjustment.",
                "sets" => [
                  %{
                    "predicate" => "state.suspension",
                    "value" => %{"summary" => "Öhlins Road & Track, street-biased alignment"}
                  },
                  %{
                    "predicate" => "state.brakes",
                    "value" => %{"summary" => "GiroDisc rotors, Ferodo DS2500 pads"}
                  }
                ]
              }
            }
          ]
        },
        %{
          date: ~D[2026-07-31],
          claims: [
            %{
              predicate: "event.plan",
              value: %{
                "text" => "Try one step softer at the rear bar before changing the alignment.",
                "area" => "handling"
              }
            }
          ]
        }
      ]
    },
    %{
      key: :gt3,
      email: "brakerain@demo.vinsanto.test",
      handle: "brakerain",
      sentence: "DMV demo · 2018 Porsche 911 GT3 Touring in Linden Green, 18,420 miles",
      claims: [
        %{predicate: "identity.model_year", value: 2018},
        %{predicate: "identity.marque", value: "porsche"},
        %{
          predicate: "identity.model",
          value: %{"code" => "911_gt3_touring", "label" => "911 GT3 Touring"}
        },
        %{predicate: "identity.market", value: "us"},
        %{predicate: "state.exterior", value: %{"summary" => "Linden Green"}},
        %{predicate: "state.wheels_tires", value: %{"summary" => "Michelin Pilot Sport Cup 2"}},
        %{predicate: "observation.mileage", value: 18_420}
      ],
      story: %{
        tagline: "The quiet-looking one that gets driven to the circuit.",
        body:
          "The Touring package made it easier to say yes, but the miles made it mine. Track days are for learning the car rather than protecting a number; the drive home is part of the event."
      },
      entries: [
        %{
          date: ~D[2026-04-20],
          claims: [
            %{
              predicate: "event.service",
              value: %{
                "summary" => "Brake fluid, alignment check, and track inspection",
                "performer" => "Independent Porsche specialist"
              }
            }
          ]
        }
      ]
    },
    %{
      key: :datsun,
      email: "zedsunday@demo.vinsanto.test",
      handle: "zedsunday",
      sentence: "DMV demo · 1978 Datsun 280Z with an LS1 and a T56, 84,201 miles",
      claims: [
        %{predicate: "identity.model_year", value: 1978},
        %{predicate: "identity.marque", value: "datsun"},
        %{
          predicate: "identity.model",
          value: %{"code" => "280z", "label" => "280Z"}
        },
        %{predicate: "identity.market", value: "us"},
        %{predicate: "state.exterior", value: %{"summary" => "Ivory White, driver finish"}},
        %{predicate: "observation.mileage", value: 84_201}
      ],
      story: %{
        tagline: "An old Z built to cross town before sunrise.",
        body:
          "The swap is the obvious part. The useful work has been cooling, brake feel, and making it start cleanly enough for a six o'clock arrival without waking the whole street."
      },
      entries: [
        %{
          date: ~D[2026-02-22],
          claims: [
            %{
              predicate: "event.modification",
              value: %{
                "summary" => "Finished the LS1 road setup",
                "area" => "drivetrain",
                "detail" => "Cooling, pedal position, and final exhaust clearance sorted.",
                "sets" => [
                  %{
                    "predicate" => "state.engine",
                    "value" => %{"summary" => "GM LS1 5.7L V8"}
                  },
                  %{
                    "predicate" => "state.transmission",
                    "value" => %{"summary" => "T56 six-speed"}
                  },
                  %{
                    "predicate" => "state.brakes",
                    "value" => %{"summary" => "Wilwood four-piston front"}
                  }
                ]
              }
            }
          ]
        }
      ]
    },
    %{
      key: :nine_twelve,
      email: "slowcarfast@demo.vinsanto.test",
      handle: "slowcarfast",
      sentence: "DMV demo · 1967 Porsche 912 in Irish Green, 72,880 miles",
      claims: [
        %{predicate: "identity.model_year", value: 1967},
        %{predicate: "identity.marque", value: "porsche"},
        %{predicate: "identity.model", value: %{"code" => "912", "label" => "912"}},
        %{predicate: "identity.market", value: "us"},
        %{predicate: "state.exterior", value: %{"summary" => "Irish Green"}},
        %{predicate: "observation.mileage", value: 72_880}
      ],
      story: %{
        tagline: "Four cylinders, thin tires, and nowhere urgent to be.",
        body:
          "It is most convincing on the two-lane roads west of Great Falls. I keep the mechanical record tidy so the car itself can remain a little scruffy."
      },
      entries: [
        %{
          date: ~D[2026-04-11],
          claims: [
            %{
              predicate: "event.service",
              value: %{
                "summary" => "Valve adjustment and carburetor synchronization",
                "performer" => "Owner"
              }
            }
          ]
        }
      ]
    }
  ]

  @events [
    %{
      key: :wdcr_ax_2,
      creator: :cayman,
      event: %{
        title: "WDCR 2026 AX Championship Event #2",
        starts_on: ~D[2026-05-24],
        starts_at: ~T[07:10:00],
        timezone: "America/New_York",
        place_text: "Regency Furniture Stadium · Waldorf, MD",
        description:
          "Washington DC Region SCCA's second 2026 Solo Championship event at Regency Furniture Stadium.",
        tags: ["WDCR", "SCCA", "autocross", "Solo"]
      },
      participations: [
        %{
          car: :cayman,
          journal:
            "Five runs made the lesson unusually clear. The car pushed through the morning offset, so I softened the rear bar one step after lunch. It rotated earlier without becoming nervous. The cone on the quickest run was entirely mine.",
          tags: ["autocross", "setup test", "Waldorf"],
          details: [
            %{label: "Class", value: "S2"},
            %{label: "Best run", value: "44.182 +1"},
            %{label: "Tire pressure", value: "32F / 30R hot"},
            %{label: "Change tried", value: "Rear bar one step softer"}
          ],
          links: [
            %{label: "WDCR registration & event details", kind: :link, url: @wdcr_ax_source}
          ]
        }
      ]
    },
    %{
      key: :wdcr_hpde_4,
      creator: :gt3,
      event: %{
        title: "WDCR HPDE/TT #4 Summit Point, Apr 24–26",
        starts_on: ~D[2026-04-24],
        ends_on: ~D[2026-04-26],
        timezone: "America/New_York",
        place_text: "Summit Point Circuit · Summit Point, WV",
        description:
          "A three-day Washington DC Region SCCA HPDE and Time Trials weekend on Summit Point's main circuit.",
        tags: ["WDCR", "SCCA", "HPDE", "time trials"]
      },
      participations: [
        %{
          car: :gt3,
          journal:
            "Friday was for rebuilding references after winter. By Saturday afternoon I could release the brake earlier into Turn 5 and let the front tire do less work. Sunday stayed deliberately boring: four clean sessions and a quiet drive home.",
          tags: ["HPDE", "Summit Point", "driver development"],
          details: [
            %{label: "Run group", value: "Intermediate"},
            %{label: "Best clean lap", value: "1:24.8"},
            %{label: "Coach", value: "Sam"},
            %{label: "Tires", value: "Michelin Pilot Sport Cup 2"}
          ],
          links: [
            %{label: "WDCR registration & event details", kind: :link, url: @wdcr_hpde_source}
          ]
        }
      ]
    },
    %{
      key: :katies_april_18,
      creator: :datsun,
      event: %{
        title: "Katie's Cars & Coffee · April 18",
        starts_on: ~D[2026-04-18],
        starts_at: ~T[06:00:00],
        ends_at: ~T[09:00:00],
        timezone: "America/New_York",
        place_text: "Katie's Coffee House · 760 Walker Rd, Great Falls, VA",
        description:
          "The long-running Saturday morning Great Falls gathering: old cars, new cars, and the people who got up early enough to bring them.",
        tags: ["cars and coffee", "Great Falls", "DMV", "weekly"]
      },
      participations: [
        %{
          car: :datsun,
          journal:
            "Arrived just after six and parked between an Avanti and a stock-looking C6. The Z drew the usual swap questions, but the useful conversation was about heat under the hood and why I kept the original gauges. Left before the exit queue formed.",
          tags: ["cars and coffee", "Datsun", "Great Falls"],
          details: [
            %{label: "Arrival", value: "6:12 AM"},
            %{label: "Parked near", value: "The Old Brogue side"},
            %{label: "Most asked about", value: "Cooling and hood clearance"},
            %{label: "Coffee", value: "Black, one refill"}
          ],
          links: [
            %{label: "Katie's Cars & Coffee community group", kind: :link, url: @katies_source},
            %{label: "DMV event listing", kind: :link, url: @katies_listing}
          ]
        },
        %{
          car: :nine_twelve,
          journal:
            "The Georgetown Pike drive was better than the parking lot. Still, an hour beside a silver 280 SL turned into three good conversations and one overdue introduction. The 912 started on the first turn when it was time to leave, which felt like showing off.",
          tags: ["cars and coffee", "air-cooled", "Great Falls"],
          details: [
            %{label: "Arrival", value: "6:34 AM"},
            %{label: "Favorite car", value: "Silver 280 SL on steel wheels"},
            %{label: "Next drive", value: "Georgetown Pike west"}
          ],
          links: [
            %{label: "Katie's Cars & Coffee community group", kind: :link, url: @katies_source},
            %{label: "DMV event listing", kind: :link, url: @katies_listing}
          ]
        }
      ]
    }
  ]

  @doc "Create or find the DMV demo garage and return its public identifiers."
  def run! do
    cars = Map.new(@cars, fn spec -> {spec.key, ensure_car!(spec)} end)

    events =
      Map.new(@events, fn spec ->
        event = ensure_event!(spec, cars)

        participations =
          Map.new(spec.participations, fn participation ->
            result = ensure_participation!(event, participation, cars)
            {participation.car, result}
          end)

        {spec.key, %{event: event, participations: participations}}
      end)

    removed_placeholder_media = remove_legacy_placeholder_media!()
    seed_conversation!(cars, events)

    %{
      cars:
        Map.new(cars, fn {key, %{vehicle: vehicle, user: user}} ->
          {key, %{public_id: vehicle.public_id, handle: user.handle}}
        end),
      events:
        Map.new(events, fn {key, %{event: event, participations: participations}} ->
          {key,
           %{
             public_id: event.public_id,
             title: event.title,
             participation_count: map_size(participations)
           }}
        end),
      removed_placeholder_media: removed_placeholder_media
    }
  end

  # Early versions of the review fixture used dead `video.example` URLs to
  # force a populated media panel. Once source links and media were separated,
  # those placeholders became actively misleading. Restrict cleanup to this
  # dataset's reserved email domain so the task never touches member content.
  defp remove_legacy_placeholder_media! do
    {count, _rows} =
      Repo.delete_all(
        from(a in EventAttachment,
          join: p in EventParticipation,
          on: p.id == a.participation_id,
          join: u in User,
          on: u.id == p.user_id,
          where:
            like(u.email, "%@demo.vinsanto.test") and
              like(a.url, "https://video.example/%")
        )
      )

    count
  end

  defp ensure_car!(spec) do
    user = ensure_user!(spec.email, spec.handle)
    scope = Scope.for_user(user)

    vehicle =
      case Repo.one(from(v in Vehicle, where: v.input == ^spec.sentence, limit: 1)) do
        %Vehicle{} = vehicle ->
          case Owners.grant_stewardship(user, vehicle) do
            {:ok, _stewardship} -> vehicle
            {:error, reason} -> raise "cannot restore demo stewardship: #{inspect(reason)}"
          end

        nil ->
          case Origination.originate_for(user, %{
                 sentence: spec.sentence,
                 claims: spec.claims,
                 method: :human
               }) do
            {:ok, %{vehicle: vehicle}} -> vehicle
            {:error, reason} -> raise "cannot originate demo car: #{inspect(reason)}"
          end
      end

    ensure_story!(scope, vehicle, spec.story)
    Enum.each(spec.entries, &ensure_entry!(scope, vehicle, &1))
    {:ok, vehicle} = SantoApi.Registry.fetch_vehicle(vehicle.id)

    %{user: user, scope: scope, vehicle: vehicle}
  end

  defp ensure_user!(email, handle) do
    user =
      case Accounts.get_user_by_email(email) do
        %User{handle: ^handle} = user -> user
        %User{} = user -> raise "demo email #{email} already holds @#{user.handle}"
        nil -> unwrap!(Accounts.register_user(%{email: email, handle: handle}), "register user")
      end

    if user.confirmed_at, do: user, else: Repo.update!(User.confirm_changeset(user))
  end

  defp ensure_story!(scope, vehicle, attrs) do
    case Stories.get_story(vehicle) do
      %{tagline: tagline, body: body}
      when tagline == attrs.tagline and body == attrs.body ->
        :ok

      _missing_or_changed ->
        unwrap!(Stories.save_story(scope, vehicle, attrs), "save story")
        :ok
    end
  end

  defp ensure_entry!(scope, vehicle, attrs) do
    desired = claim_set(attrs.claims)

    exists? =
      Enum.any?(Owners.timeline(scope, vehicle), fn entry ->
        entry.date == attrs.date and claim_set(entry.claims) == desired
      end)

    unless exists?, do: unwrap!(Owners.compose_entry(scope, vehicle, attrs), "compose entry")
  end

  defp claim_set(claims) do
    claims
    |> Enum.map(fn claim ->
      {Map.get(claim, :predicate) || Map.get(claim, "predicate"),
       Map.get(claim, :value) || Map.get(claim, "value")}
    end)
    |> MapSet.new()
  end

  defp ensure_event!(spec, cars) do
    creator = Map.fetch!(cars, spec.creator).user
    attrs = spec.event

    query =
      from(e in EventOccurrence,
        where:
          e.creator_user_id == ^creator.id and e.title == ^attrs.title and
            e.starts_on == ^attrs.starts_on and e.place_text == ^attrs.place_text,
        limit: 1
      )

    case Repo.one(query) do
      %EventOccurrence{} = event ->
        event
        |> EventOccurrence.changeset(attrs)
        |> Repo.update!()

      nil ->
        %EventOccurrence{
          public_id: EventOccurrence.mint_public_id(),
          creator_user_id: creator.id,
          source_status: :community
        }
        |> EventOccurrence.changeset(attrs)
        |> Repo.insert!()
    end
  end

  defp ensure_participation!(event, spec, cars) do
    car = Map.fetch!(cars, spec.car)

    case Repo.get_by(EventParticipation, event_id: event.id, vehicle_id: car.vehicle.id) do
      %EventParticipation{} = participation ->
        participation =
          Repo.preload(participation, [:event, :user, :vehicle, attachments: :artifact])

        sync_links!(participation, spec.links)

        Repo.preload(
          participation,
          [:event, :user, :vehicle, attachments: :artifact],
          force: true
        )

      nil ->
        attrs = %{
          event_id: event.id,
          participation: %{
            journal: spec.journal,
            tags: spec.tags,
            details: spec.details,
            visibility: :public
          },
          links: spec.links
        }

        result = unwrap!(Events.create_participation(car.scope, car.vehicle, attrs), "join event")
        result.participation
    end
  end

  defp sync_links!(participation, links) do
    links
    |> Enum.with_index()
    |> Enum.each(fn {attrs, position} ->
      attachment =
        Enum.find(participation.attachments, fn attachment ->
          attachment.label == attrs.label and attachment.kind == attrs.kind
        end) || %EventAttachment{participation_id: participation.id}

      attachment
      |> EventAttachment.changeset(Map.put(attrs, :position, position))
      |> Repo.insert_or_update!()
    end)
  end

  defp seed_conversation!(cars, events) do
    ax = participation!(events, :wdcr_ax_2, :cayman)
    hpde = participation!(events, :wdcr_hpde_4, :gt3)
    katies_z = participation!(events, :katies_april_18, :datsun)
    katies_912 = participation!(events, :katies_april_18, :nine_twelve)

    ensure_like!(cars.gt3.scope, cars.cayman.vehicle, ax.entry_ref)
    ensure_like!(cars.nine_twelve.scope, cars.datsun.vehicle, katies_z.entry_ref)
    ensure_like!(cars.datsun.scope, cars.nine_twelve.vehicle, katies_912.entry_ref)

    ensure_comment!(
      cars.gt3.scope,
      cars.cayman.vehicle,
      ax.entry_ref,
      "That bar change reads like the right lesson. Keep the alignment still for Event #3."
    )

    ensure_comment!(
      cars.cayman.scope,
      cars.gt3.vehicle,
      hpde.entry_ref,
      "Four clean sessions and the drive home is a result I trust."
    )

    ensure_comment!(
      cars.nine_twelve.scope,
      cars.datsun.vehicle,
      katies_z.entry_ref,
      "The original gauges were the right choice. I walked past twice before noticing the swap."
    )

    ensure_comment!(
      cars.datsun.scope,
      cars.nine_twelve.vehicle,
      katies_912.entry_ref,
      "Next Saturday: same departure, then keep going west instead of turning into the lot."
    )
  end

  defp participation!(events, event_key, car_key) do
    events |> Map.fetch!(event_key) |> Map.fetch!(:participations) |> Map.fetch!(car_key)
  end

  defp ensure_like!(scope, vehicle, entry_ref) do
    unless Social.conversation(scope, vehicle, entry_ref).liked? do
      case Social.toggle_like(scope, vehicle, entry_ref) do
        {:ok, :added} -> :ok
        other -> raise "cannot seed like: #{inspect(other)}"
      end
    end
  end

  defp ensure_comment!(%Scope{user: user} = scope, vehicle, entry_ref, body) do
    exists? =
      Social.conversation(scope, vehicle, entry_ref).comments
      |> Enum.any?(&(&1.author_user_id == user.id and &1.body == body))

    unless exists?,
      do: unwrap!(Social.create_comment(scope, vehicle, entry_ref, %{body: body}), "reply")
  end

  defp unwrap!({:ok, value}, _step), do: value
  defp unwrap!({:error, reason}, step), do: raise("cannot #{step}: #{inspect(reason)}")
end
