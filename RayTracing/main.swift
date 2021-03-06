import Foundation
import simd


typealias Color = SIMD3<Double>
typealias Point = SIMD3<Double>
typealias Vector = SIMD3<Double>

final class StandardErrorOutputStream: TextOutputStream {
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

var outputStream = StandardErrorOutputStream()
func printErr(_ string: String) {
    print(string, to: &outputStream)
}


extension SIMD3 where Scalar == Double {
    var length: Double {
        sqrt(lengthSquared)
    }

    var lengthSquared: Double {
        dot(self)
    }

    var unitVector: Self {
        self / self.length
    }

    var colorString: String {
        let clamped = simd.clamp(self, min: 0.0, max: 0.999)
        return "\(Int(256.0 * clamped.x)) \(Int(256.0 * clamped.y)) \(Int(256.0 * clamped.z))"
    }

    func colorString(samples: Int) -> String {
        (self / Double(samples)).squareRoot().colorString
    }

    func dot(_ o: SIMD3<Scalar>) -> Scalar {
        simd.dot(self, o)
    }

    func cross(_ o: SIMD3<Scalar>) -> SIMD3<Scalar> {
        simd.cross(self, o)
    }

    var isNearZero: Bool {
        let s = 1e-8
        return abs(x) < s && abs(y) < s && abs(z) < s
    }

    func reflect(normal: Self) -> Self {
        self - 2 * self.dot(normal) * normal
    }

    func refract(normal: Vector, etaiOverEtat: Double) -> Self {
        let cosTheta = Swift.min((-self).dot(normal), 1.0)
        let rOutPerp = etaiOverEtat * (self + cosTheta * normal)
        let rOutParallel = -abs(1.0 - rOutPerp.lengthSquared).squareRoot() * normal
        return rOutPerp + rOutParallel
    }

    static func random() -> Self {
        Self(x: Double.random(in: 0.0..<1.0),
             y: Double.random(in: 0.0..<1.0),
             z: Double.random(in: 0.0..<1.0))
    }

    static func random(min: Double, max: Double) -> Self {
        Self(x: Double.random(in: min...max),
             y: Double.random(in: min...max),
             z: Double.random(in: min...max))
    }

    static func randomInUnitSphere() -> Self {
        while(true) {
            let point = random(min: -1.0, max: 1.0)
            if point.lengthSquared <= 1 {
                return point
            }
        }
    }

    static func randomUnitVector() -> Self {
        randomInUnitSphere().unitVector
    }

    func randomInHemisphere() -> Self {
        let inUnitSphere = Self.randomInUnitSphere()
        if inUnitSphere.dot(self) > 0.0 {
            return inUnitSphere
        } else {
            return -inUnitSphere
        }
    }

    static func randomInUnitDisk() -> Self {
        while true {
            let p = Vector(x: Double.random(in: 0...1.0),
                           y: Double.random(in: 0...1.0),
                           z: 0.0)
            if p.length <= 1.0 {
                return p
            }
        }
    }
}

extension Color {
    init(r: Scalar, g: Scalar, b: Scalar) {
        self.init(x: r, y: g, z: b)
    }

    var r: Scalar { x }
    var g: Scalar { y }
    var b: Scalar { z }

    static let white: Color = .init(r: 1.0, g: 1.0, b: 1.0)
    static let black: Color = .init(r: 0.0, g: 0.0, b: 0.0)
    static let red: Color = .init(r: 1.0, g: 0.0, b: 0.0)
    static let blue: Color = .init(r: 0.0, g: 0.0, b: 1.0)
}

struct Ray {
    let origin: Point
    let direction: Vector

    func at(_ t: Double) -> Point {
        origin + t * direction
    }
}

struct HitRecord {
    let point: Point
    let normal: Vector
    var material: Material
    let t: Double
    let frontFace: Bool

    init(ray: Ray, t: Double, outwardNormal: Vector, material: Material) {
        self.t = t
        point = ray.at(t)
        frontFace = ray.direction.dot(outwardNormal) < 0
        normal = frontFace ? outwardNormal : -outwardNormal
        self.material = material
    }
}

protocol Hittable {
    func hit(ray: Ray, tMin: Double, tMax: Double) -> HitRecord?
}

protocol Material: AnyObject {
    func scatter(ray: Ray, hit: HitRecord) -> (attenuation: Color, scattered: Ray)?
}

class Lambertian: Material {
    let albedo: Color

    init(albedo: Color) {
        self.albedo = albedo
    }

    func scatter(ray: Ray, hit: HitRecord) -> (attenuation: Color, scattered: Ray)? {
        var scatterDirection = hit.normal + Vector.randomUnitVector()

        if scatterDirection.isNearZero {
            scatterDirection = hit.normal
        }

        return (
            attenuation: albedo,
            scattered: Ray(origin: hit.point, direction: scatterDirection)
        )
    }
}

class Metal : Material {
    let albedo: Color
    let fuzz: Double

    init(albedo: Color, fuzz: Double) {
        self.albedo = albedo
        self.fuzz = fuzz
    }

    func scatter(ray: Ray, hit: HitRecord) -> (attenuation: Color, scattered: Ray)? {
        let reflected = ray.direction.unitVector.reflect(normal: hit.normal)
        let scattered = Ray(origin: hit.point, direction: reflected + fuzz * Vector.randomInUnitSphere())
        if dot(scattered.direction, hit.normal) > 0 {
            return (
                attenuation: albedo,
                scattered: scattered
            )
        } else {
            return nil
        }
    }
}

class Dielectric: Material {
    let ir: Double

    init(ir: Double) {
        self.ir = ir
    }

    func scatter(ray: Ray, hit: HitRecord) -> (attenuation: Color, scattered: Ray)? {
        let refractionRatio = hit.frontFace ? 1.0 / ir : ir

        let unitDirection = ray.direction.unitVector
        let cosTheta = Swift.min(-unitDirection.dot(hit.normal), 1.0)
        let sinTheta = (1.0 - cosTheta * cosTheta).squareRoot()

        let cannotRefract = refractionRatio * sinTheta > 1.0;

        let direction: Vector
        if cannotRefract || reflectance(cosTheta, refractionRatio) > Double.random(in: 0...1.0) {
            direction = reflect(unitDirection, n: hit.normal);
        } else {
            direction = refract(unitDirection, n: hit.normal, eta: refractionRatio);
        }
        return (
            attenuation: .white,
            scattered: Ray(origin: hit.point, direction: direction)
        )
    }

    func reflectance(_ cosine: Double, _ refrationIndex: Double) -> Double {
        var r0 = (1 - refrationIndex) / (1 + refrationIndex)
        r0 = r0 * r0
        return r0 + (1 - r0) * pow(1 - cosine, 5)
    }
}

struct Sphere: Hittable {
    let center: Point
    let radius: Double
    let material: Material

    func hit(ray: Ray, tMin: Double, tMax: Double) -> HitRecord? {
        let originToCenter = ray.origin - center;
        let a = ray.direction.lengthSquared
        let half_b = originToCenter.dot(ray.direction)
        let c = originToCenter.lengthSquared - radius * radius
        let discriminant = half_b * half_b - a * c
        guard discriminant > 0.0 else { return nil }
        let sqrtDiscriminant = sqrt(discriminant)

        var root = (-half_b - sqrtDiscriminant) / a
        if root < tMin || root > tMax {
            root = (-half_b + sqrtDiscriminant) / a
            if root < tMin || root > tMax {
                return nil
            }
        }
        let hitPoint = ray.at(root)
        return HitRecord(ray: ray, t: root, outwardNormal: (hitPoint - center) / radius, material: material)
    }
}

struct HittableList: Hittable {
    var objects = [Hittable]()

    func hit(ray: Ray, tMin: Double, tMax: Double) -> HitRecord? {
        var closestRecord: HitRecord?
        for object in objects {
            let tMax = closestRecord?.t ?? tMax
            if let hitRecord = object.hit(ray: ray, tMin: tMin, tMax: tMax) {
                closestRecord = hitRecord
            }
        }
        return closestRecord
    }
}

func deg2rad(_ number: Double) -> Double {
    number * .pi / 180
}

struct Camera {
    let origin: Point
    let lowerLeftCorner: Point
    let horizontal: Vector
    let vertical: Vector
    let u, v, w: Vector
    let lenseRadius: Double

    init(
        lookFrom: Point,
        lookAt: Point,
        vup: Vector,
        verticalFieldOfView: Double,
        aspectRatio: Double,
        aperture: Double,
        focusDistance: Double
    ) {
        let theta = deg2rad(verticalFieldOfView)
        let h = tan(theta / 2)
        let viewportHeight = 2.0 * h;
        let viewportWidth = aspectRatio * viewportHeight;

        w = (lookFrom - lookAt).unitVector
        u = vup.cross(w).unitVector
        v = w.cross(u)

        origin = lookFrom
        horizontal = focusDistance * viewportWidth * u
        vertical = focusDistance * viewportHeight * v
        lowerLeftCorner = origin - horizontal / 2 - vertical / 2 - focusDistance * w

        lenseRadius = aperture / 2
    }

    func getRay(s: Double, t: Double) -> Ray {
        let rd = lenseRadius * Vector.randomInUnitDisk()
        let offset = u * rd.x + v * rd.y
        return Ray(
            origin: origin + offset,
            direction: lowerLeftCorner + s * horizontal + t * vertical - origin - offset
        )
    }
}

let groundMaterial = Lambertian(albedo: .init(r: 0.8, g: 0.8, b: 0.0))
let pinkDiffuse = Lambertian(albedo: .init(r: 0.7, g: 0.3, b: 0.3))
let darkBlueDiffuse = Lambertian(albedo: .init(r: 0.1, g: 0.2, b: 0.5))
let redDiffuse = Lambertian(albedo: .red)
let blueDiffuse = Lambertian(albedo: .blue)
let metal1 = Metal(albedo: .init(r: 0.8, g: 0.8, b: 0.3), fuzz: 0.3)
let metal2 = Metal(albedo: .init(r: 0.8, g: 0.6, b: 0.2), fuzz: 1.0)
let metal3 = Metal(albedo: .init(r: 0.8, g: 0.6, b: 0.2), fuzz: 0.0)
let glass1_5 = Dielectric(ir: 1.5)
func randomScene() -> HittableList {
    var world = HittableList()

    let groundMaterial = Lambertian(albedo: .init(r: 0.5, g: 0.5, b: 0.5))
    world.objects.append(Sphere(center: Point(x: 0.0, y: -1000.0, z: 0.0), radius: 1000.0, material: groundMaterial))

    for a in -11..<11 {
        for b in -11..<11 {
            let chooseMaterial = Double.random(in: 0...1.0)
            let center =  Point(x: Double(a) + 0.9 * Double.random(in: 0...1.0),
                                y: 0.2,
                                z: Double(b) + 0.9 * Double.random(in: 0...1.0))

            if (center - Point(x: 4.0, y: 0.2, z: 0.0)).length > 0.9 {
                let material: Material
                switch chooseMaterial {
                case ..<0.8:
                    let albedo = Color.random() * Color.random()
                    material = Lambertian(albedo: albedo)
                case ..<0.95:
                    let albedo = Color.random(min: 0.5, max: 1)
                    let fuzz = Double.random(in: 0...0.5)
                    material = Metal(albedo: albedo, fuzz: fuzz)
                default:
                    material = Dielectric(ir: 1.5)
                }
                world.objects.append(Sphere(center: center, radius: 0.2, material: material))
            }
        }
    }

    let material1 = Dielectric(ir: 1.5)
    world.objects.append(Sphere(center: Point(x: 0.0, y: 1.0, z: 0.0), radius: 1.0, material: material1))
    let material2 = Lambertian(albedo: .init(r: -4, g: 1.0, b: 0.0))
    world.objects.append(Sphere(center: Point(x: -4.0, y: 1.0, z: 0.0), radius: 1.0, material: material2))
    let material3 = Metal(albedo: .init(r: 0.7, g: 0.6, b: 0.5), fuzz: 0.0)
    world.objects.append(Sphere(center: Point(x: 4.0, y: 1.0, z: 0.0), radius: 1.0, material: material3))

    return world
}

//let world = HittableList(objects: [
//    Sphere(center: Point(x: 0.0, y: -100.5, z: -1.0), radius: 100.0, material: groundMaterial),
//    Sphere(center: Point(x: 0.0, y: 0.0, z: -1.0), radius: 0.5, material: darkBlueDiffuse),
//    Sphere(center: Point(x: -1.0, y: 0.0, z: -1.0), radius: 0.5, material: glass1_5),
//    Sphere(center: Point(x: 1.0, y: 0.0, z: -1.0), radius: 0.5, material: metal3),
//])


//let R = cos(Double.pi / 4)
//
//let world = HittableList(objects: [
//    Sphere(center: Point(x: -R, y: 0.0, z: -1.0), radius: R, material: blueDiffuse),
//    Sphere(center: Point(x: R, y: 0.0, z: -1.0), radius: R, material: redDiffuse),
//])

let world = randomScene()

func color(for ray: Ray, depth: Int) -> Color {
    guard depth > 0 else { return Color.black }
    if let hit = world.hit(ray: ray, tMin: 0.001, tMax: Double.infinity) {
        if let (attenuation, scattered) = hit.material.scatter(ray: ray, hit: hit) {
            return attenuation * color(for: scattered, depth: depth - 1)
        } else {
            return Color.black
        }
    } else {
        let t = 0.5 * (ray.direction.unitVector.y + 1.0)
        return (1.0 - t) * Color.white + t * Color(r: 0.5, g: 0.7, b: 1.0)
    }
}


// Image
let aspectRatio = 3.0 / 2.0
let imageWidth = 1200
let imageHeight = Int(Double(imageWidth) / aspectRatio)
let samplesPerPixel = 500
let maxDepth = 50

// Camera

let lookFrom = Point(x: 13.0, y: 2.0, z: 3.0)
let lookAt = Point(x: 0.0, y: 0.0, z: 0.0)
let camera = Camera(
    lookFrom: lookFrom,
    lookAt: lookAt,
    vup: Vector(x: 0.0, y: 1.0, z: 0.0),
    verticalFieldOfView: 20.0,
    aspectRatio: aspectRatio,
    aperture: 0.1,
    focusDistance: 10.0
)

// Render

print("P3\n\(imageWidth) \(imageHeight)\n255")
for _j in 0..<imageHeight {
    let j = imageHeight - 1 - _j
    printErr("\rScanlines remaining: \(j) ")
    for i in 0..<imageWidth {
        var pixelColor = Color(r: 0.0, g: 0.0, b: 0.0)
        for _ in 0..<samplesPerPixel {
            let u = (Double(i) + Double.random(in: 0..<1)) / Double(imageWidth - 1)
            let v = (Double(j) + Double.random(in: 0..<1)) / Double(imageHeight - 1)

            let ray = camera.getRay(s: u, t: v)
            pixelColor += color(for: ray, depth: maxDepth)
        }
        print(pixelColor.colorString(samples: samplesPerPixel))
    }
}
printErr("\nDone.\n")
